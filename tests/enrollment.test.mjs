import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
const db=await PGlite.create({extensions:{pgcrypto}});
await db.exec(`create role anon;create role authenticated;create schema auth;create schema extensions;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
await db.exec(readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8'));
await db.exec(readFileSync(new URL('../supabase/002_enrollment.sql',import.meta.url),'utf8'));
const names=['Samuel','Gabi','Gabriel','Mirella','Vanessa'];
const ids=Array.from({length:7},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
for(let i=0;i<ids.length;i++)await db.query('insert into auth.users values($1,$2,$3)',[ids[i],`person${i}@example.test`,i===6?null:new Date().toISOString()]);
async function as(role,id,fn){await db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${role};`);try{return await fn()}finally{await db.exec('reset role')}}
const ownerInvite=(await db.exec(readFileSync(new URL('../supabase/bootstrap-organizador.sql',import.meta.url),'utf8'))).flatMap(r=>r.rows).find(r=>r.convite_privado_de_samuel)?.convite_privado_de_samuel;
assert.match(ownerInvite,/^[0-9a-f]{32}$/);
await as('anon',null,()=>assert.rejects(db.query('select public.claim_profile($1)',[ownerInvite]),/permission denied/));
await as('authenticated',ids[6],()=>assert.rejects(db.query('select public.claim_profile($1)',[ownerInvite]),/Confirme o e-mail/));
await as('authenticated',ids[0],async()=>assert.equal((await db.query('select public.claim_profile($1) as name',[ownerInvite])).rows[0].name,'Samuel'));
await as('authenticated',ids[5],async()=>{
  await assert.rejects(db.query('select public.claim_profile($1)',['0'.repeat(32)]),/inválido/);
  await assert.rejects(db.query('select public.claim_profile($1)',[ownerInvite]),/inválido/);
  await assert.rejects(db.query("select public.create_participant_invite('Gabi')"),/organizador/);
  await assert.rejects(db.query('select * from private.enrollment_invites'),/permission denied/);
});
const invites={};
for(const name of names.slice(1))invites[name]=await as('authenticated',ids[0],async()=>(await db.query('select public.create_participant_invite($1) as code',[name])).rows[0].code);
const replaced=invites.Gabi;
invites.Gabi=await as('authenticated',ids[0],async()=>(await db.query("select public.create_participant_invite('Gabi') as code")).rows[0].code);
await as('authenticated',ids[1],()=>assert.rejects(db.query('select public.claim_profile($1)',[replaced]),/inválido/));
await db.query("update private.enrollment_invites set expires_at=now()-interval '1 minute' where participant_name='Vanessa'");
await as('authenticated',ids[4],()=>assert.rejects(db.query('select public.claim_profile($1)',[invites.Vanessa]),/inválido/));
invites.Vanessa=await as('authenticated',ids[0],async()=>(await db.query("select public.create_participant_invite('Vanessa') as code")).rows[0].code);
for(let i=1;i<5;i++)await as('authenticated',ids[i],async()=>assert.equal((await db.query('select public.claim_profile($1) as name',[invites[names[i]]])).rows[0].name,names[i]));
await as('authenticated',ids[1],async()=>{
 assert.equal((await db.query('select public.claim_profile($1) as name',[ownerInvite])).rows[0].name,'Gabi');
 assert.deepEqual((await db.query('select name from public.participants')).rows.map(r=>r.name),['Gabi']);
 await assert.rejects(db.query("update public.participants set is_admin=true where name='Gabi'"),/permission denied/);
 await assert.rejects(db.query('select public.draw_once()'),/organizador/);
 await assert.rejects(db.query('select * from public.assignments'),/permission denied/);
});
await as('authenticated',ids[0],async()=>{
 await assert.rejects(db.query("select public.create_participant_invite('Gabi')"),/já tem uma conta/);
 await db.query('select public.draw_once()');
 await assert.rejects(db.query('select public.draw_once()'),/já foi realizado/);
});
const assignments=(await db.query('select * from public.assignments order by giver')).rows;
assert.equal(assignments.length,5);assert.equal(new Set(assignments.map(a=>a.recipient)).size,5);assert(assignments.every(a=>a.giver!==a.recipient));
for(let i=0;i<5;i++)await as('authenticated',ids[i],async()=>{
 const own=(await db.query('select public.my_result() as result')).rows[0].result;
 const recipient=assignments.find(a=>a.giver===ids[i]).recipient;
 assert.equal(own.name,names[ids.indexOf(recipient)]);
 assert.deepEqual(Object.keys(own).sort(),['name','wish']);
 await db.query('select public.claim_profile($1)',[ownerInvite]);
});
assert.deepEqual((await db.query('select * from public.assignments order by giver')).rows,assignments);
console.log('PASS: verified-email enrollment, secret invites, expiration, replacement, one-profile-per-account, RLS, admin-only access, single draw and result persistence.');
await db.close();
