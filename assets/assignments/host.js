// Trusted parent only. The generated document lives in a separate opaque
// origin. Native WebKit also checks that bridge messages come from this frame.
(() => {
  'use strict';
  const frame = document.getElementById('assignment');
  let latest = window.__studyhubAnswers;
  let pending = null;
  let ready = false;
  let saveTimer;
  delete window.__studyhubAnswers;
  const native = packet => window.webkit.messageHandlers.assignment.postMessage(JSON.stringify(packet));
  addEventListener('message', e => {
    if (e.source !== frame.contentWindow || !e.data || typeof e.data.type !== 'string') return;
    if (e.data.type === 'studyhub:ready') {ready=true;native({type:'ready'});return;}
    if (e.data.type === 'studyhub:error') {
      const error = typeof e.data.message === 'string' ? e.data.message.slice(0,300) : 'Answers could not be saved.';
      native({type:'error',message:error});
      if(pending){clearTimeout(pending.timer);pending.reject(Error(error));pending=null;}
      return;
    }
    if (e.data.type !== 'studyhub:state' || typeof e.data.answers !== 'string') return;
    const json=e.data.answers;
    if(new TextEncoder().encode(json).length>4194304)return;
    try {
      const value=JSON.parse(json);
      if(!value||Array.isArray(value)||typeof value!=='object')return;
      latest=json;
      clearTimeout(saveTimer);
      if (pending) native({type:'state',answers:latest});
      else saveTimer=setTimeout(()=>native({type:'state',answers:latest}),250);
      if(pending){clearTimeout(pending.timer);pending.resolve(latest);pending=null;}
    } catch(_) {native({type:'error',message:'The assignment returned invalid answers.'});}
  });
  window.studyhubFlush=()=>new Promise((resolve,reject)=>{
    if(!ready){reject(Error('Wait for the assignment to load.'));return;}
    if(pending){reject(Error('An answer snapshot is already pending.'));return;}
    pending={resolve,reject,timer:setTimeout(()=>{pending=null;reject(Error('The assignment did not respond. Reopen it to retry.'));},5000)};
    frame.contentWindow.postMessage({type:'studyhub:flush'},'*');
  });
  const content=window.__studyhubDocument;delete window.__studyhubDocument;
  frame.srcdoc=content;
})();
