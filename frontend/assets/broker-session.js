/* Reuse Supabase's refresh flow before deciding that the user must sign in. */
HZ.requireSession=async function(){
  const active=HZ.session();if(active)return active;
  try{
    const {createClient}=await import('https://esm.sh/@supabase/supabase-js@2');
    HZ._sessionClient ||= createClient('https://ceoqtkbpdxnkuptnnwjg.supabase.co','sb_publishable_akQqDzkDbBhYJP0q6Z4Dtg_xjQh_Xfb');
    const {data,error}=await HZ._sessionClient.auth.getSession();
    if(error)throw error;
    if(data.session){
      const session=HZ.session();
      if(session){location.reload();return null;}
    }
    location.replace('/login?next='+encodeURIComponent(location.pathname+location.search));
  }catch(e){
    const host=document.getElementById('app');
    if(host)host.innerHTML='<div class="workspace-empty" role="alert"><h2>تعذّر التحقق من الجلسة</h2><p>راجع اتصالك وحاول تاني.</p><button class="btn btn-teal" onclick="location.reload()">إعادة المحاولة</button></div>';
  }
  return null;
};
