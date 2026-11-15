import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
const db=await PGlite.create({extensions:{pgcrypto}});
const sql=f=>readFileSync(new URL('../supabase/'+f,import.meta.url),'utf8');
await db.exec(`create role anon;create role authenticated;create schema auth;create schema extensions;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
for(const f of ['schema.sql','002_enrollment.sql','003_code_access.sql','004_permanent_profiles.sql'])await db.exec(sql(f));
const codes=(await db.exec(sql('gerar-codigos.sql')))[0].rows;
async function rpc(fn,args){await db.exec('set role anon');try{return (await db.query(`select public.${fn}(${args.map((_,i)=>'$'+(i+1)).join(',')}) as data`,args)).rows[0].data}finally{await db.exec('reset role')}}
const tokens={};for(const c of codes)tokens[c.name]=(await rpc('open_profile',[c.name,c.codigo_individual])).token;
await rpc('save_profile_wishes',[tokens.Gabi,['Livro','',''],'Histórias','Verde','Perfume','','Preferência por livros']);
await db.exec(sql('005_gift_links.sql'));
const original=await rpc('profile_state',[tokens.Gabi]);assert.deepEqual(original.wish.suggestions,['Livro','','']);assert.deepEqual(original.wish.links,['','','']);
const links=['','https://loja.example/presente?cor=verde&modelo=2','http://outra.example/item'];
await rpc('save_profile_wishes',[tokens.Gabi,['Livro','Camisa',''],...['Histórias','Verde','Perfume','','Preferência por livros'],links]);
assert.deepEqual((await rpc('profile_state',[tokens.Gabi])).wish.links,links);
// Legacy callers omit links and must never erase a participant's saved URLs.
await rpc('save_profile_wishes',[tokens.Gabi,['Livro novo','Camisa',''],'Histórias','Verde','Perfume','','']);
assert.deepEqual((await rpc('profile_state',[tokens.Gabi])).wish.links,links);
for(const invalid of [['javascript:alert(1)'],['data:text/html,evil'],['https://loja.example/a b'],['https://loja.example/<script>'],['https://loja.example/'+ 'x'.repeat(2048)],['','','',''],[null]])await assert.rejects(rpc('save_profile_wishes',[tokens.Gabi,['Livro','',''],'','','','','',invalid]),/links válidos/);
assert.deepEqual((await rpc('profile_state',[tokens.Gabi])).wish.links,links,'rejected edits leave saved links intact');
await rpc('save_profile_wishes',[tokens.Mirella,['','',''],'','','','','',[' https://loja.example/so-link ','','']]);
assert.equal((await db.query("select wishes_filled from public.participation_status where name='Mirella'")).rows[0].wishes_filled,true);
assert.equal((await rpc('profile_state',[tokens.Mirella])).wish.links[0],'https://loja.example/so-link');
await rpc('initialize_code_draw',[tokens.Samuel]);
const pairs=(await db.query('select * from private.code_assignments order by giver')).rows;
for(const name of Object.keys(tokens))await rpc('reveal_secret',[tokens[name]]);
for(const pair of pairs){const p=await rpc('profile_state',[tokens[pair.giver]]);assert.equal(p.result.name,pair.recipient);if(pair.recipient==='Gabi')assert.deepEqual(p.result.wish.links,links);assert.equal(p.name,pair.giver)}
await db.exec('set role anon');await assert.rejects(db.query('select * from private.code_wishes'),/permission denied/);await db.exec('reset role');
await rpc('save_profile_wishes',[tokens.Gabi,['Livro novo','',''],'','','','','',['','','']]);
assert.deepEqual((await rpc('profile_state',[tokens.Gabi])).wish.links,['','','']);
assert.deepEqual((await db.query('select * from private.code_assignments order by giver')).rows,pairs);
await assert.rejects(rpc('save_profile_wishes',['0'.repeat(64),['','',''],'','','','','',links]),/inválido|expirado/);
console.log('PASS: gift URLs persist by suggestion slot, HTTP(S) validation, link-only wishes, old-client compatibility, private recipient access and unchanged draw.');
await db.close();
