import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
const sql=f=>readFileSync(new URL('../supabase/'+f,import.meta.url),'utf8');
const db=await PGlite.create({extensions:{pgcrypto}});
await db.exec(`create role anon;create role authenticated;create schema auth;create schema extensions;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
for(const f of ['schema.sql','002_enrollment.sql','003_code_access.sql','004_permanent_profiles.sql','005_gift_links.sql'])await db.exec(sql(f));
async function rpc(fn,args=[]){await db.exec('set role anon');try{return (await db.query(`select public.${fn}(${args.map((_,i)=>'$'+(i+1)).join(',')}) as data`,args)).rows[0].data}finally{await db.exec('reset role')}}
const legacyCodes=(await db.exec(sql('gerar-codigos.sql'))).flatMap(r=>r.rows);
const oldTokens={};for(const c of legacyCodes)oldTokens[c.name]=(await rpc('open_profile',[c.name,c.codigo_individual])).token;
await rpc('save_profile_wishes',[oldTokens.Samuel,['Livro da edição original','',''],'Original','Azul','','M','Guardar tudo',['https://original.example/livro','','']]);
await rpc('initialize_code_draw',[oldTokens.Samuel]);for(const t of Object.values(oldTokens))await rpc('reveal_secret',[t]);
const oldResult=await rpc('profile_state',[oldTokens.Samuel]);
const before=(await db.query(sql('verificar-edicao-original.sql'))).rows[0].resumo_integridade_edicao1;
await db.exec(sql('006_second_edition.sql'));
assert.equal((await db.query(sql('verificar-edicao-original.sql'))).rows[0].resumo_integridade_edicao1,before,'migration leaves every legacy row unchanged');
const names=['Samuel','Gabi','Carol','Nanda','Isa','Douglas'];
const dir=(await db.query('select * from public.edition2_participant_directory order by name')).rows;
assert.equal(dir.length,6);assert.equal(new Set(dir.map(p=>p.id)).size,6);
for(const n of ['Samuel','Gabi']){const a=(await db.query('select id,photo from public.participant_directory where name=$1',[n])).rows[0],b=dir.find(p=>p.name===n);assert.notEqual(a.id,b.id);assert.equal(a.photo,b.photo)}
for(const n of ['Carol','Nanda','Isa','Douglas'])assert.equal(dir.find(p=>p.name===n).photo,`participants/${n.toLowerCase()}.png`);
for(const fn of ['edition2_profile_state','edition2_reveal_secret','edition2_admin_dashboard'])await assert.rejects(rpc(fn,[oldTokens.Samuel]),/inválido|expirado/);
const newCodes=(await db.exec(sql('gerar-codigos-edicao2.sql'))).flatMap(r=>r.rows).filter(r=>r.codigo_individual);
assert.equal(newCodes.length,6);assert.equal(new Set(newCodes.map(c=>c.codigo_individual)).size,6);
assert.equal((await db.exec(sql('gerar-codigos-edicao2.sql'))).flatMap(r=>r.rows).filter(r=>r.codigo_individual).length,0,'bootstrap does not rotate codes');
const tokens={};for(const c of newCodes){tokens[c.name]=(await rpc('edition2_open_profile',[c.name,c.codigo_individual])).token;const p=await rpc('edition2_profile_state',[tokens[c.name]]);assert.equal(p.name,c.name);assert.equal(p.result,null);assert.deepEqual(p.wish,{})}
for(const n of ['Samuel','Gabi']){assert.notEqual(newCodes.find(c=>c.name===n).codigo_individual,legacyCodes.find(c=>c.name===n).codigo_individual);assert((await rpc('edition2_open_profile',[n,legacyCodes.find(c=>c.name===n).codigo_individual])).error)}
for(const fn of ['profile_state','reveal_secret','admin_dashboard'])await assert.rejects(rpc(fn,[tokens.Samuel]),/inválido|expirado/);
const pairs=(await db.query('select * from private.edition2_assignments order by giver')).rows;
assert.equal(pairs.length,6);assert.equal(new Set(pairs.map(p=>p.recipient)).size,6);assert(pairs.every(p=>p.giver!==p.recipient));
await assert.rejects(rpc('edition2_initialize_code_draw',[tokens.Samuel]),/não pode ser refeito/);
await assert.rejects(rpc('edition2_admin_dashboard',[tokens.Carol]),/exclusiva/);
await assert.rejects(rpc('edition2_save_code_event',[tokens.Carol,null,'Outro local',10,100,'']),/administrador/);
for(const name of names){const r=await rpc('edition2_reveal_secret',[tokens[name]]);assert.equal(r.name,pairs.find(p=>p.giver===name).recipient);assert.deepEqual(r.wish,{});await assert.rejects(rpc('edition2_reveal_secret',[tokens[name]]),/já participou/)}
// Late wishes, gift links, independent event and access recovery.
await rpc('edition2_save_profile_wishes',[tokens.Samuel,['Presente novo','',''],'Segunda edição','Verde','','GG','Independente',['https://nova.example/presente','','']]);
const giver=pairs.find(p=>p.recipient==='Samuel').giver;
assert.deepEqual((await rpc('edition2_profile_state',[tokens[giver]])).result.wish.suggestions,['Presente novo','','']);
assert.equal((await rpc('edition2_profile_state',[tokens[giver]])).result.wish.links[0],'https://nova.example/presente');
await rpc('edition2_save_code_event',[tokens.Samuel,'2026-12-25T20:00:00-03:00','Novo local',50,200,'Somente segunda edição']);
const oldIds=(await db.query('select id from public.participant_directory order by name')).rows;
const carol=dir.find(p=>p.name==='Carol');
await assert.rejects(rpc('edition2_save_participant_photo',[tokens.Carol,carol.id,'x']),/administrador/);
await assert.rejects(rpc('edition2_save_participant_photo',[tokens.Samuel,oldIds[0].id,'data:image/webp;base64,UklGRjAwMDBXRUJQAAAA']),/não encontrado/);
const newCarol=await rpc('edition2_recover_participant_code',[tokens.Samuel,carol.id,'Confirmação presencial da participante']);
await assert.rejects(rpc('edition2_profile_state',[tokens.Carol]),/inválido|expirado/);
tokens.Carol=(await rpc('edition2_open_profile',['Carol',newCarol.code])).token;
assert.equal((await rpc('edition2_profile_state',[tokens.Carol])).result.name,pairs.find(p=>p.giver==='Carol').recipient);
assert.deepEqual((await db.query('select * from private.edition2_assignments order by giver')).rows,pairs);
await db.exec('set role anon');
assert.equal((await db.query('select name from public.edition2_participation_status where revealed_at is null')).rows.length,0);
for(const t of ['private.edition2_assignments','private.edition2_wishes','private.edition2_access','private.edition2_sessions','private.edition2_audit'])await assert.rejects(db.query('select * from '+t),/permission denied/);
await assert.rejects(db.query("update public.edition2_participation_status set revealed_at=null"),/permission denied/);
await assert.rejects(db.query('select private.edition2_draw_once()'),/permission denied/);
await db.exec('reset role');
assert.equal((await db.query(sql('verificar-edicao-original.sql'))).rows[0].resumo_integridade_edicao1,before,'all second-edition activity leaves original codes, sessions, photos, wishes, results, event and statuses unchanged');
assert.deepEqual(await rpc('profile_state',[oldTokens.Samuel]),oldResult,'original profile remains available');
assert.equal((await rpc('edition2_admin_dashboard',[tokens.Samuel])).assignment_count,6);
console.log('PASS: first-edition integrity digest unchanged, distinct identities/PINs/sessions, six valid unique pairs, photo mapping, permanent access, late wishes/links, isolated admin operations, RLS and no repeat draw.');
await db.close();
