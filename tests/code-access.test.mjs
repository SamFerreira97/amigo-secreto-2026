import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
const db=await PGlite.create({extensions:{pgcrypto}});
await db.exec(`create role anon;create role authenticated;create schema auth;create schema extensions;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
for(const file of ['schema.sql','002_enrollment.sql','003_code_access.sql'])await db.exec(readFileSync(new URL('../supabase/'+file,import.meta.url),'utf8'));
const codes=(await db.exec(readFileSync(new URL('../supabase/gerar-codigos.sql',import.meta.url),'utf8')))[0].rows;
assert.equal(codes.length,5);assert.equal(new Set(codes.map(c=>c.codigo_individual)).size,5);
assert.equal((await db.exec(readFileSync(new URL('../supabase/gerar-codigos.sql',import.meta.url),'utf8')))[0].rows.length,0);
const tokens={};
async function anon(fn){await db.exec('set role anon');try{return await fn()}finally{await db.exec('reset role')}}
async function rpc(name,args=[]){return anon(async()=>(await db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) as data`,args)).rows[0].data)}
await anon(async()=>{
 assert.equal((await db.query('select name,revealed_at from public.participation_status')).rows.length,5);
 for(const table of ['public.assignments','public.participants','private.profile_access','private.code_assignments','private.code_wishes'])await assert.rejects(db.query('select * from '+table),/permission denied/);
 await assert.rejects(db.query("update public.participation_status set revealed_at=null"),/permission denied/);
 await assert.rejects(db.query('select public.draw_once()'),/permission denied/);
 await assert.rejects(db.query("select public.claim_profile('abc')"),/permission denied/);
});
await assert.rejects(rpc('open_profile',['Samuel','0'.repeat(32)]),/inválido/);
const sam=codes.find(c=>c.name==='Samuel');const gabi=codes.find(c=>c.name==='Gabi');
await assert.rejects(rpc('open_profile',['Samuel',gabi.codigo_individual]),/inválido/);
for(const c of codes){assert.match(c.codigo_individual,/^[0-9a-f]{32}$/);tokens[c.name]=(await rpc('open_profile',[c.name,c.codigo_individual])).token;assert.match(tokens[c.name],/^[0-9a-f]{64}$/);assert.equal((await rpc('profile_state',[tokens[c.name]])).result,null)}
const old=tokens.Samuel;tokens.Samuel=(await rpc('open_profile',['Samuel',sam.codigo_individual])).token;
await assert.rejects(rpc('profile_state',[old]),/inválido/);
await assert.rejects(rpc('reveal_secret',['f'.repeat(64)]),/inválido/);
assert.equal((await db.query('select count(*) as n from private.code_assignments')).rows[0].n,0);
await rpc('save_profile_wishes',[tokens.Gabi,['Livro','Camisa','Chocolate'],'M','Verde','Perfume']);
await assert.rejects(rpc('save_profile_wishes',[tokens.Gabi,['1','2','3','4'],'','','']),/check constraint/);
await assert.rejects(rpc('save_code_event',[tokens.Gabi,null,'Teste',10,50]),/organizador/);
await rpc('save_code_event',[tokens.Samuel,'2026-12-25T19:00:00-03:00','Casa da família',50,150]);
const samResult=await rpc('reveal_secret',[tokens.Samuel]);assert.notEqual(samResult.name,'Samuel');
const assignments=(await db.query('select * from private.code_assignments order by giver')).rows;
assert.equal(assignments.length,5);assert.equal(new Set(assignments.map(a=>a.recipient)).size,5);assert(assignments.every(a=>a.giver!==a.recipient));
await assert.rejects(rpc('reveal_secret',[tokens.Samuel]),/já participou/);
await assert.rejects(rpc('open_profile',['Samuel',sam.codigo_individual]),/indisponível/);
assert.equal((await rpc('profile_state',[tokens.Samuel])).result.name,samResult.name);
assert.equal((await anon(()=>db.query('select name from public.participation_status where revealed_at is null'))).rows.length,4);
for(const c of codes.filter(c=>c.name!=='Samuel')){
 const result=await rpc('reveal_secret',[tokens[c.name]]);
 assert.equal(result.name,assignments.find(a=>a.giver===c.name).recipient);
 assert.deepEqual(Object.keys(result).sort(),['name','wish']);
 if(result.name==='Gabi')assert.deepEqual(result.wish.suggestions,['Livro','Camisa','Chocolate']);
 await assert.rejects(rpc('open_profile',[c.name,c.codigo_individual]),/indisponível/);
}
await db.query("update public.participants set is_admin=true where name='Samuel'");
await rpc('save_profile_wishes',[tokens.Gabi,['Livro novo'],'','','']);
assert.deepEqual((await db.query('select * from private.code_assignments order by giver')).rows,assignments);
assert.equal((await anon(()=>db.query('select name from public.participation_status where revealed_at is null'))).rows.length,0);
assert.equal((await rpc('profile_state',[tokens.Gabi])).revealed,true);
assert.equal((await db.query('select drawn from public.event')).rows[0].drawn,true);
console.log('PASS: private codes, token isolation/rotation, no pre-reveal result, permanent one-time reveal, uniform derangement constraints, immutable mappings, RLS, wishes and organizer permissions.');
await db.close();
