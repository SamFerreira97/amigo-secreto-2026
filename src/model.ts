import {createClient} from '@supabase/supabase-js';
export const env=(import.meta as unknown as {env:Record<string,string>}).env;
export const appUrl=new URL(env.BASE_URL,window.location.href).href;
export type Edition=1|2;
export const editionNames:Record<Edition,string[]>={1:['Samuel','Gabi','Gabriel','Mirella','Vanessa'],2:['Samuel','Gabi','Carol','Nanda','Isa','Douglas']};
export function editionUrl(edition:Edition){const url=new URL(appUrl);url.searchParams.set('edicao',String(edition));return url.href}
export function editionTable(edition:Edition,table:string){return edition===2?'edition2_'+table:table}
export const db=env.VITE_SUPABASE_URL&&env.VITE_SUPABASE_ANON_KEY?createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_ANON_KEY,{auth:{persistSession:false,detectSessionInUrl:false,autoRefreshToken:false}}):null;
export type Wish={suggestions:string[];links:string[];preferences:string;colors:string;avoid:string;sizes:string;notes:string};
export type Result={name:string;wish:Partial<Wish>};
export type Profile={name:string;id:string;is_admin:boolean;drawn:boolean;revealed:boolean;result:Result|null;wish:Partial<Wish>};
export type Person={id:string;name:string;photo:string;photo_updated:boolean;position:string;color:string};
export type Status={name:string;revealed_at:string|null;wishes_filled:boolean};
export type Event={exchange_at:string|null;location:string;min_value:number|null;max_value:number|null;message:string;drawn:boolean};
export type AdminPerson=Person&Status;
export type Audit={action:string;target:string|null;reason:string|null;created_at:string};
export type AdminState={participants:(Status&{id:string})[];drawn:boolean;assignment_count:number;audit:Audit[]};
export const emptyWish:Wish={suggestions:['','',''],links:['','',''],preferences:'',colors:'',avoid:'',sizes:'',notes:''};
export const emptyEvent:Event={exchange_at:null,location:'A combinar com a turma',min_value:null,max_value:null,message:'',drawn:false};
const decorations:Record<string,{position:string;color:string}>={Samuel:{position:'50% 42%',color:'#f3ded2'},Gabi:{position:'50% 38%',color:'#e5ebd8'},Gabriel:{position:'45% 31%',color:'#eddfc8'},Mirella:{position:'51% 16%',color:'#dce8e7'},Vanessa:{position:'50% 24%',color:'#ece0e6'},Carol:{position:'50% 32%',color:'#efd8cf'},Nanda:{position:'50% 19%',color:'#dce7d8'},Isa:{position:'50% 30%',color:'#ecdfc7'},Douglas:{position:'50% 42%',color:'#dce4e2'}};
export function personFromRow(p:{id:string;name:string;photo:string;photo_updated:boolean}):Person{return {...p,...decorations[p.name],photo:p.photo.startsWith('data:')?p.photo:env.BASE_URL+p.photo,position:p.photo_updated?'50% 50%':decorations[p.name]?.position??'50% 50%'}}
export function normalizeWish(w:Partial<Wish>):Wish{return {...emptyWish,...w,suggestions:[0,1,2].map(i=>w.suggestions?.[i]??''),links:[0,1,2].map(i=>w.links?.[i]??'')}}
export function safeGiftUrl(value:string|undefined):string|null{if(!value?.trim())return null;try{const url=new URL(value.trim());return ['https:','http:'].includes(url.protocol)&&url.hostname?url.href:null}catch{return null}}
export function hasWish(w:Partial<Wish>){return Object.values(w).some(v=>Array.isArray(v)?v.some(s=>s.trim()):typeof v==='string'&&v.trim())}
export class ApiError extends Error {constructor(message:string,public retryAfter=0){super(message)}}
export async function rpc<T=unknown>(name:string,args:Record<string,unknown>):Promise<T>{if(!db)throw new ApiError('A conexão segura não está disponível.');const{data,error}=await db.rpc(name,args);if(error)throw new ApiError(error.message);if(data?.error)throw new ApiError(data.error,data.retry_after??0);return data as T}
export function editionRpc<T=unknown>(edition:Edition,name:string,args:Record<string,unknown>):Promise<T>{return rpc<T>(edition===2?'edition2_'+name:name,args)}
export const wishFields=[['colors','Cores favoritas'],['sizes','Tamanhos de roupa ou calçado'],['preferences','Gostos e interesses'],['avoid','O que prefiro não ganhar'],['notes','Observações adicionais']] as const;
