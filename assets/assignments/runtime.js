// Runs inside the opaque-origin assignment frame. This is convenience code,
// not a security boundary: the host validates every packet from this frame.
(() => {
  'use strict';
  let answers = Object.assign(Object.create(null), window.__studyhubInitialAnswers);
  delete window.__studyhubInitialAnswers;
  let timer;
  const canvases = new Map();
  const dirtyCanvases = new Set();
  const clone = value => JSON.parse(JSON.stringify(value));
  const send = () => {
    clearTimeout(timer);
    try {
      for (const key of dirtyCanvases) {
        const canvas = canvases.get(key);
        const image = document.createElement('canvas');
        image.width=canvas.width;image.height=canvas.height;
        const context=image.getContext('2d');
        context.fillStyle='white';context.fillRect(0,0,image.width,image.height);
        context.drawImage(canvas,0,0);
        answers[key]={kind:'ink',png:image.toDataURL('image/png')};
      }
      dirtyCanvases.clear();
      const json = JSON.stringify(answers);
      if (new TextEncoder().encode(json).length > 4194304) throw Error('Your answers are too large to save. Reduce or clear a sketch and retry.');
      parent.postMessage({type:'studyhub:state', answers:json}, '*');
    } catch (e) { parent.postMessage({type:'studyhub:error', message:String(e.message)}, '*'); }
  };
  const schedule = () => { clearTimeout(timer); timer = setTimeout(send, 250); };
  const setAnswer = (key, value) => {
    if (typeof key !== 'string' || !key || key.length > 256) throw Error('Invalid answer key');
    answers[key] = clone(value);
    schedule();
  };
  window.studyhub = Object.freeze({
    getAnswer: key => answers[key] === undefined ? null : clone(answers[key]),
    setAnswer,
    clearInk: key => {
      const canvas = canvases.get(key);
      if (canvas) { canvas.getContext('2d').clearRect(0,0,canvas.width,canvas.height);dirtyCanvases.delete(key);setAnswer(key, null); }
    }
  });
  // Only the containing host can request a flush. An assignment cannot invoke
  // AI, select a Lecture, navigate the app or access credentials through this API.
  addEventListener('message', e => {
    if (e.source === parent && e.data?.type === 'studyhub:flush') send();
  });
  document.addEventListener('submit', e => e.preventDefault());
  document.addEventListener('DOMContentLoaded', async () => {
    const restored = [];
    document.querySelectorAll('[data-answer-key]').forEach(el => {
      const key = el.getAttribute('data-answer-key');
      if (!key || key.length > 256) return;
      const saved = answers[key];
      if (el instanceof HTMLCanvasElement) {
        if (canvases.size >= 12 || canvases.has(key)) return;
        canvases.set(key, el);
        // Fixed logical dimensions: resizing the viewport never loses ink.
        el.width = Math.max(1,Math.min(1600,el.width || 800));
        el.height = Math.max(1,Math.min(1600,el.height || 400));
        el.style.touchAction = 'none';
        const ctx = el.getContext('2d');
        if (!ctx) return;
        if (saved?.kind === 'ink' && typeof saved.png === 'string' && saved.png.startsWith('data:image/png;base64,')) {
          restored.push(new Promise(resolve => {
            const image = new Image();
            image.onload = () => {ctx.drawImage(image,0,0,el.width,el.height);resolve();};
            image.onerror = resolve;
            image.src = saved.png;
          }));
        }
        let active = null;
        const point = e => { const r = el.getBoundingClientRect();return [(e.clientX-r.left)*el.width/r.width,(e.clientY-r.top)*el.height/r.height]; };
        const save = () => { dirtyCanvases.add(key);schedule(); };
        el.addEventListener('pointerdown', e => {
          if (active !== null || e.button !== 0) return;
          e.preventDefault(); active=e.pointerId;el.setPointerCapture(active);
          // Dark ink stays readable when exported for multimodal review.
          ctx.strokeStyle='#173043';ctx.fillStyle='#173043';ctx.lineWidth=3;ctx.lineCap='round';ctx.lineJoin='round';
          const [x,y]=point(e);ctx.beginPath();ctx.arc(x,y,1.5,0,Math.PI*2);ctx.fill();ctx.beginPath();ctx.moveTo(x,y);save();
        });
        el.addEventListener('pointermove',e=>{if(e.pointerId!==active)return;const [x,y]=point(e);ctx.lineTo(x,y);ctx.stroke();save();});
        const finish=e=>{if(e.pointerId===active){active=null;save();}};
        el.addEventListener('pointerup',finish);el.addEventListener('pointercancel',finish);
      } else if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) {
        if (el instanceof HTMLInputElement && (el.type==='file'||el.type==='password')) {el.disabled=true;return;}
        if (saved !== undefined) {
          if (el instanceof HTMLSelectElement && el.multiple) {
            const selected = new Set(Array.isArray(saved) ? saved : [String(saved ?? '')]);
            for (const option of el.options) option.selected = selected.has(option.value);
          }
          else if (el.type==='checkbox') el.checked = saved === true;
          else if (el.type==='radio') el.checked = saved === el.value;
          else el.value = String(saved ?? '');
        }
        const update=()=>{
          if(el.type==='radio'&&!el.checked)return;
          const value = el instanceof HTMLSelectElement && el.multiple
            ? Array.from(el.options).filter(option=>option.selected).map(option=>option.value)
            : el.type==='checkbox'?el.checked:el.value;
          setAnswer(key,value);
        };
        el.addEventListener('input',update);el.addEventListener('change',update);
      }
    });
    await Promise.all(restored);
    parent.postMessage({type:'studyhub:ready'},'*');
  });
})();
