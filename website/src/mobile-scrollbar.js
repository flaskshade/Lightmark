export function installMobileScrollbar(window) {
  const surface = window.querySelector('.document-surface');
  const editor = window.querySelector('.editor');
  const track = document.createElement('div');
  track.className = 'mobile-scroll-track';
  const thumb = document.createElement('div');
  thumb.className = 'mobile-scroll-thumb';
  thumb.setAttribute('aria-hidden','true');
  track.append(thumb);
  window.append(track);
  const owner = () => editor.hidden ? surface : editor;
  let metrics = { travel:0,max:0 };
  function update() {
    const scroller = owner();
    // Follow the actual content viewport, including the mobile CSS zoom.
    const frame = window.getBoundingClientRect();
    const content = surface.getBoundingClientRect();
    const scale = frame.height / Math.max(1, window.offsetHeight);
    track.style.top = `${(content.top - frame.top) / scale + 3}px`;
    track.style.bottom = `${(frame.bottom - content.bottom) / scale + 3}px`;
    const height = track.clientHeight;
    const max = Math.max(0,scroller.scrollHeight-scroller.clientHeight);
    const size = Math.min(height,Math.max(36,height * scroller.clientHeight / Math.max(1,scroller.scrollHeight)));
    metrics = {travel:Math.max(0,height-size),max};
    thumb.style.height = `${size}px`;
    thumb.style.transform = `translateY(${max ? scroller.scrollTop/max*metrics.travel : 0}px)`;
    track.classList.toggle('no-overflow',max===0);
  }
  let drag = null;
  track.addEventListener('pointerdown',event => {
    if (!metrics.max) return;
    event.preventDefault();
    track.setPointerCapture(event.pointerId);
    const rect = track.getBoundingClientRect();
    const scale = rect.height / track.clientHeight;
    if (event.target !== thumb) {
      owner().scrollTop = Math.max(0,Math.min(metrics.max,((event.clientY-rect.top)/scale-thumb.clientHeight/2)/metrics.travel*metrics.max));
    }
    drag = {y:event.clientY,top:owner().scrollTop,scale};
  });
  track.addEventListener('pointermove',event => {
    if (drag && metrics.travel) owner().scrollTop = drag.top+(event.clientY-drag.y)/drag.scale/metrics.travel*metrics.max;
  });
  const stop = () => {drag=null;};
  track.addEventListener('pointerup',stop);
  track.addEventListener('pointercancel',stop);
  track.addEventListener('lostpointercapture',stop);
  surface.addEventListener('scroll',update,{passive:true});
  editor.addEventListener('scroll',update,{passive:true});
  editor.addEventListener('input',update);
  const resize = new ResizeObserver(update);
  resize.observe(surface);
  resize.observe(track);
  resize.observe(window);
  globalThis.addEventListener('load',update);
  document.fonts.ready.then(update);
  globalThis.addEventListener('orientationchange',() => requestAnimationFrame(update));
  new MutationObserver(update).observe(surface,{attributes:true,childList:true,subtree:true,attributeFilter:['hidden','class']});
  update();
}
