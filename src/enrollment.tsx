import {useState} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';

export function Enrollment({client,onComplete}:{client:SupabaseClient;onComplete:()=>void}) {
  const [code,setCode]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
  async function claim(){
    setBusy(true);setError('');
    try {
      const {error}=await client.rpc('claim_profile',{invitation_code:code.trim()});
      if(error)throw error;
      onComplete();
    }catch(e){setError(e instanceof Error?e.message:(e as {message?:string})?.message??'Não foi possível vincular o perfil.');}
    finally{setBusy(false);}
  }
  return <><span className="eyebrow dark">SEU E-MAIL FOI CONFIRMADO</span><h2>Seu convite, seu perfil</h2>
    <p>Cole o convite individual enviado pelo organizador. Ele vincula seu e-mail ao seu perfil uma única vez.</p>
    <form onSubmit={e=>{e.preventDefault();void claim();}}>
      <label>Convite individual<input autoComplete="off" spellCheck={false} autoCapitalize="none" required minLength={32} maxLength={48} value={code} onChange={e=>setCode(e.target.value)} placeholder="Cole aqui seu convite"/></label>
      <button className="primary" disabled={busy||!code.trim()}>{busy?'Vinculando…':'Concluir meu cadastro'}</button>
    </form>
    {error&&<p className="status" role="alert">{error}</p>}
    <p>O convite não contém o resultado do sorteio. Se ainda não recebeu o seu, peça ao organizador.</p>
  </>;
}

export function InvitePanel({client,names}:{client:SupabaseClient;names:string[]}) {
  const [codes,setCodes]=useState<Record<string,string>>({}),[busy,setBusy]=useState(''),[message,setMessage]=useState('');
  async function issue(name:string){
    setBusy(name);setMessage('');
    try {
      const {data,error}=await client.rpc('create_participant_invite',{participant_name:name});
      if(error)throw error;
      setCodes(old=>({...old,[name]:String(data)}));
    }catch(e){setMessage(e instanceof Error?e.message:(e as {message?:string})?.message??'Não foi possível gerar o convite.');}
    finally{setBusy('');}
  }
  async function copy(name:string){
    try{await navigator.clipboard.writeText(codes[name]);setMessage(`Convite de ${name} copiado.`)}
    catch{setMessage('Selecione e copie o convite exibido abaixo.')}
  }
  return <section className="invite-admin"><hr/><h3>Convites individuais</h3>
    <p>Cada participante informa o próprio e-mail e usa seu convite para vincular o perfil. Envie cada código somente à pessoa indicada.</p>
    <p>Gerar um convite substitui qualquer convite anterior ainda não usado para o mesmo perfil. A validade é de 30 dias.</p>
    {names.map(name=><div key={name} className="invite-admin-row"><b>{name}</b>{codes[name]?<><code>{codes[name]}</code><button type="button" onClick={()=>void copy(name)}>Copiar convite</button></>:<button type="button" disabled={Boolean(busy)} onClick={()=>void issue(name)}>{busy===name?'Gerando…':'Gerar convite'}</button>}</div>)}
    {message&&<p className="status" role="status">{message}</p>}
  </section>;
}
