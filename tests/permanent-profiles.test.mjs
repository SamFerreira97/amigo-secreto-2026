import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
const sql=file=>readFileSync(new URL('../supabase/'+file,import.meta.url),'utf8');
async function setup(){const db=await PGlite.create({extensions:{pgcrypto}});await db.exec(`create role anon;create role authenticated;create schema auth;create schema extensions;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);for(const f of ['schema.sql','002_enrollment.sql','003_code_access.sql'])await db.exec(sql(f));return db}
const db=await setup();
const codes=(await db.exec(sql('gerar-codigos.sql')))[0].rows;
async function anon(fn){await db.exec('set role anon');try{return await fn()}finally{await db.exec('reset role')}}
async function rpc(name,args=[]){return anon(async()=>(await db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) as data`,args)).rows[0].data)}
const oldSam=(await rpc('open_profile',['Samuel',codes.find(c=>c.name==='Samuel').codigo_individual])).token;
await db.exec(sql('004_permanent_profiles.sql'));
assert.equal((await rpc('profile_state',[oldSam])).name,'Samuel','existing session preserved');
const tokens={Samuel:oldSam};
const hashes=(await db.query('select name,code_hash from private.profile_access order by name')).rows;
const directory=(await anon(()=>db.query('select * from public.participant_directory order by name'))).rows;
assert.equal(new Set(directory.map(p=>p.id)).size,5);
for(const c of codes){const opened=await rpc('open_profile',[c.name,c.codigo_individual]);assert(opened.token);tokens[c.name]=opened.token;const p=await rpc('profile_state',[opened.token]);assert.equal(p.name,c.name);assert.equal(p.result,null);assert.equal(p.is_admin,c.name==='Samuel')}
assert.equal((await rpc('profile_state',[oldSam])).name,'Samuel','another device does not log out existing device');
for(const table of ['private.code_wishes','private.code_assignments','private.profile_access','private.code_sessions','private.admin_audit','public.assignments'])await anon(()=>assert.rejects(db.query('select * from '+table),/permission denied/));
await anon(()=>assert.rejects(db.query("update public.participant_directory set photo='x'"),/permission denied/));
for(const [fn,args] of [['admin_dashboard',[tokens.Gabi]],['initialize_code_draw',[tokens.Gabi]],['save_code_event',[tokens.Gabi,null,'Casa',10,50,'Olá']],['recover_participant_code',[tokens.Gabi,directory[0].id,'Confirmação presencial']],['save_participant_photo',[tokens.Gabi,directory[0].id,'data:image/webp;base64,AAAA']]])await assert.rejects(rpc(fn,args),/administrador|exclusiva/);
// Failed requests commit their counters. A correct PIN cannot bypass the timed block.
for(let i=0;i<5;i++)assert((await rpc('open_profile',['Mirella','0'.repeat(32)])).error);
assert((await rpc('open_profile',['Mirella',codes.find(c=>c.name==='Mirella').codigo_individual])).retry_after>0);
await db.query("update private.profile_access set blocked_until=now()-interval '1 second' where name='Mirella'");
assert((await rpc('open_profile',['Mirella',codes.find(c=>c.name==='Mirella').codigo_individual])).token);
assert.equal((await db.query("select failed_attempts from private.profile_access where name='Mirella'")).rows[0].failed_attempts,0);
// Desired behavior: only the organizer initializes; reveal cannot silently draw.
await assert.rejects(rpc('reveal_secret',[tokens.Gabi]),/inicializou/);
assert.equal((await db.query('select count(*) as n from private.code_assignments')).rows[0].n,0);
await rpc('save_profile_wishes',[tokens.Gabi,['Livro','',''],'Música','Verde','Perfume','M / 38','Preferência por livrarias']);
await rpc('initialize_code_draw',[tokens.Samuel]);
await assert.rejects(rpc('initialize_code_draw',[tokens.Samuel]),/não pode ser refeito/);
const assignments=(await db.query('select * from private.code_assignments order by giver')).rows;
assert.equal(assignments.length,5);assert.equal(new Set(assignments.map(a=>a.recipient)).size,5);assert(assignments.every(a=>a.giver!==a.recipient));
const dashboard=await rpc('admin_dashboard',[tokens.Samuel]);assert.equal(dashboard.assignment_count,5);assert.equal(dashboard.participants.length,5);assert(!JSON.stringify(dashboard).includes('recipient'));assert(!JSON.stringify(dashboard).includes('code_hash'));
// Concurrent calls queued through a real PostgreSQL engine: one reveal wins, the other rejects.
await db.exec('set role anon');
const competing=await Promise.allSettled([db.query('select public.reveal_secret($1) as result',[tokens.Samuel]),db.query('select public.reveal_secret($1) as result',[oldSam])]);
await db.exec('reset role');
assert.equal(competing.filter(r=>r.status==='fulfilled').length,1);assert.equal(competing.filter(r=>r.status==='rejected').length,1);
const samResult=(await rpc('profile_state',[tokens.Samuel])).result;
const samAgain=await rpc('open_profile',['Samuel',codes.find(c=>c.name==='Samuel').codigo_individual]);
assert.equal((await rpc('profile_state',[samAgain.token])).result.name,samResult.name,'used profile opens on a second device');
const statuses=(await anon(()=>db.query('select * from public.participation_status'))).rows;
assert.equal(statuses.filter(s=>!s.revealed_at).length,4);assert.equal(statuses.filter(s=>s.wishes_filled).length,1);
for(const c of codes.filter(c=>c.name!=='Samuel')){
 const result=await rpc('reveal_secret',[tokens[c.name]]);
 assert.equal(result.name,assignments.find(a=>a.giver===c.name).recipient);
 const state=await rpc('profile_state',[tokens[c.name]]);assert.equal(state.result.name,result.name);
 if(result.name==='Gabi')assert.equal(result.wish.sizes,'M / 38');
}
// Wishes added later become visible to only the assigned giver, with no re-draw.
const target=assignments.find(a=>a.recipient!=='Gabi');
assert.deepEqual((await rpc('profile_state',[tokens[target.giver]])).result.wish,{});
await rpc('save_profile_wishes',[tokens[target.recipient],['Chocolate','',''],'','','','','']);
assert.deepEqual((await rpc('profile_state',[tokens[target.giver]])).result.wish.suggestions,['Chocolate','','']);
const idsBefore=directory.map(p=>p.id);
// Minimal RIFF/WEBP header fixture: database accepts image-only data, never HTML/URL scripts.
const photo='data:image/webp;base64,'+Buffer.from('RIFF0000WEBPVP8 '+String.fromCharCode(0)).toString('base64');
await rpc('save_participant_photo',[tokens.Samuel,directory[0].id,photo]);
assert.equal((await db.query('select photo from public.participant_directory where id=$1',[directory[0].id])).rows[0].photo,photo);
await assert.rejects(rpc('save_participant_photo',[tokens.Samuel,directory[0].id,'data:text/html;base64,AAAA']),/WebP/);
assert.deepEqual((await db.query('select id from public.participant_directory order by name')).rows.map(p=>p.id),idsBefore);
const gabiId=directory.find(p=>p.name==='Gabi').id;
await assert.rejects(rpc('recover_participant_code',[tokens.Samuel,gabiId,'oi']),/identidade/);
const recovered=await rpc('recover_participant_code',[tokens.Samuel,gabiId,'Identidade confirmada presencialmente']);
assert.match(recovered.code,/^[0-9a-f]{32}$/);
await assert.rejects(rpc('profile_state',[tokens.Gabi]),/inválido|expirado/);
assert((await rpc('open_profile',['Gabi',codes.find(c=>c.name==='Gabi').codigo_individual])).error);
const newGabi=(await rpc('open_profile',['Gabi',recovered.code])).token;
assert.equal((await rpc('profile_state',[newGabi])).result.name,assignments.find(a=>a.giver==='Gabi').recipient);
await rpc('save_code_event',[tokens.Samuel,'2026-12-25T20:00:00-03:00','Casa da família',50,150,'Vamos celebrar juntos!']);
assert.equal((await anon(()=>db.query('select message from public.event'))).rows[0].message,'Vamos celebrar juntos!');
assert.deepEqual((await db.query('select * from private.code_assignments order by giver')).rows,assignments);
assert.equal((await anon(()=>db.query('select name from public.participation_status where revealed_at is null'))).rows.length,0);
assert.equal((await rpc('admin_dashboard',[tokens.Samuel])).audit.filter(a=>a.action==='recover_access').length,1);
const hashesAfter=(await db.query('select name,code_hash from private.profile_access order by name')).rows;
assert.deepEqual(hashesAfter.filter(p=>p.name!=='Gabi'),hashes.filter(p=>p.name!=='Gabi'));
await rpc('close_profile',[newGabi]);await assert.rejects(rpc('profile_state',[newGabi]),/inválido|expirado/);
await db.close();
// Upgrade an already-drawn group: existing identities, wishes, status and results survive.
const existing=await setup();
const existingCodes=(await existing.exec(sql('gerar-codigos.sql')))[0].rows;
const eSam=(await existing.query('select public.open_profile($1,$2) as v',['Samuel',existingCodes.find(c=>c.name==='Samuel').codigo_individual])).rows[0].v.token;
await existing.query('select public.save_profile_wishes($1,$2,$3,$4,$5)',[eSam,['Preservar'],'','','']);
await existing.query('select public.reveal_secret($1)',[eSam]);
const before=(await existing.query('select * from private.code_assignments order by giver')).rows;
await existing.exec(sql('004_permanent_profiles.sql'));
assert.deepEqual((await existing.query('select * from private.code_assignments order by giver')).rows,before);
const preserved=(await existing.query('select public.profile_state($1) as v',[eSam])).rows[0].v;
assert.equal(preserved.revealed,true);assert.deepEqual(preserved.wish.suggestions,['Preservar']);
assert.equal((await existing.query("select wishes_filled from public.participation_status where name='Samuel'")).rows[0].wishes_filled,true);
await existing.close();
console.log('PASS: permanent PIN access, persisted rate limit, existing data/session migration, admin-only draw/photos/recovery, one-time reveal, competing requests, late wishes, profile IDs, audit, RLS and unchanged pairings.');
