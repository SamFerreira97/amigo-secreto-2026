// Isolated localhost-only browser QA database. Never used by the deployed app.
import http from 'node:http';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
const db=await PGlite.create({extensions:{pgcrypto}});
await db.exec(`create role anon;create role authenticated;create schema auth;create schema extensions;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
for(const f of ['schema.sql','002_enrollment.sql','003_code_access.sql','004_permanent_profiles.sql'])await db.exec(readFileSync(new URL('../supabase/'+f,import.meta.url),'utf8'));
const names=['Samuel','Gabi','Gabriel','Mirella','Vanessa'];
for(let i=0;i<names.length;i++)await db.query("insert into private.profile_access(name,code_hash) values($1,extensions.digest($2,'sha256'))",[names[i],String(i+1).repeat(32)]);
const signatures={open_profile:['participant_name','secret_code'],profile_state:['access_token'],initialize_code_draw:['access_token'],reveal_secret:['access_token'],save_profile_wishes:['access_token','suggestions','preferences','colors','avoid','sizes','notes'],save_code_event:['access_token','exchange_at','location','min_value','max_value','message'],admin_dashboard:['access_token'],save_participant_photo:['access_token','participant_id','photo_data'],recover_participant_code:['access_token','participant_id','recovery_reason'],close_profile:['access_token']};
const tables={participant_directory:['id','name','photo','photo_updated','updated_at'],participation_status:['name','revealed_at','wishes_filled'],event:['exchange_at','location','min_value','max_value','message','drawn']};
let queue=Promise.resolve();
const server=http.createServer(async(req,res)=>{
 res.setHeader('Access-Control-Allow-Origin','http://127.0.0.1:5173');res.setHeader('Access-Control-Allow-Headers','*');res.setHeader('Access-Control-Allow-Methods','GET,POST,OPTIONS');res.setHeader('Content-Type','application/json');res.setHeader('Cache-Control','no-store');
 if(req.method==='OPTIONS'){res.writeHead(204).end();return}
 const url=new URL(req.url,'http://127.0.0.1');let body='';for await(const chunk of req)body+=chunk;
 const next=queue.then(async()=>{await db.exec('set role anon');try{
  const path=url.pathname.replace('/rest/v1/','');
  if(path.startsWith('rpc/')&&req.method==='POST'){
   const fn=path.slice(4),keys=signatures[fn];if(!keys)throw Error('Unknown test RPC');const data=JSON.parse(body);const args=keys.map(k=>data[k]);
   const result=await db.query(`select public.${fn}(${args.map((_,i)=>'$'+(i+1)).join(',')}) as data`,args);res.end(JSON.stringify(result.rows[0].data));
  }else if(tables[path]&&req.method==='GET'){
   const columns=(url.searchParams.get('select')??'').split(',');if(!columns.every(c=>tables[path].includes(c)))throw Error('Unsupported test selection');
   const rows=(await db.query(`select ${columns.join(',')} from public.${path}`)).rows;res.end(JSON.stringify(path==='event'?rows[0]:rows));
  }else{res.writeHead(404).end(JSON.stringify({message:'Unknown test endpoint'}))}
 }catch(e){res.writeHead(400).end(JSON.stringify({message:e.message}))}finally{await db.exec('reset role')}});queue=next.catch(()=>{});await next;
});
server.listen(54399,'127.0.0.1',()=>console.log('Isolated SQL QA backend: http://127.0.0.1:54399'));
process.on('SIGINT',()=>server.close(()=>{void db.close().then(()=>process.exit(0))}));
