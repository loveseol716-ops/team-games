import { createClient } from 'npm:@supabase/supabase-js@2';

const allowedOrigins = new Set(['https://arcstation.kr','https://www.arcstation.kr']);
Deno.serve(async (req: Request) => {
 const origin=req.headers.get('origin')||'';
 const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':allowedOrigins.has(origin)?origin:'https://arcstation.kr','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(origin&&!allowedOrigins.has(origin))return reply({error:'ORIGIN_NOT_ALLOWED'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'');
 if(!token)return reply({error:'AUTH_REQUIRED'},401);
 const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const service=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 // Explicit online token validation; never trust decoded claims or user metadata.
 const {data:{user},error:authError}=await service.auth.getUser(token);
 if(authError||!user)return reply({error:'AUTH_REQUIRED'},401);
 const {data:admin,error:roleError}=await service.from('tg_admins').select('user_id').eq('user_id',user.id).maybeSingle();
 if(roleError||!admin)return reply({error:'ADMIN_ONLY'},403);
 let body;try{body=await req.json();}catch{return reply({error:'INVALID_REQUEST'},400);}
 if(body.action!=='delete'||!body.user_id||typeof body.email!=='string'||typeof body.reason!=='string')return reply({error:'INVALID_REQUEST'},400);
 const scoped=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false}});
 const {error:checkError}=await scoped.rpc('arc_admin_action',{p_action:'delete_check',p_payload:{user_id:body.user_id,email:body.email,reason:body.reason}});
 if(checkError)return reply({error:checkError.message},400);
 // The auth.users BEFORE DELETE guard rechecks history within the deletion transaction.
 const {error}=await service.auth.admin.deleteUser(body.user_id);
 if(error)return reply({error:'DELETE_FAILED'},409);
 return reply({deleted:true});
});
