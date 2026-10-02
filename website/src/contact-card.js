const card = document.querySelector('.contact-card-tilt');
const items = card.querySelectorAll('[data-depth]');
const enabled = matchMedia('(hover:hover) and (pointer:fine) and (prefers-reduced-motion:no-preference)');
const reset = () => {
  card.style.transform = 'rotateY(0deg) rotateX(0deg)';
  items.forEach(item => { item.style.transform = 'translateZ(0px)'; });
};
card.addEventListener('pointerenter', () => {
  if (enabled.matches) items.forEach(item => { item.style.transform = `translateZ(${item.dataset.depth}px)`; });
});
card.addEventListener('pointermove', event => {
  if (!enabled.matches || event.pointerType !== 'mouse') return;
  const {left,top,width,height} = card.getBoundingClientRect();
  const x = (event.clientX-left-width/2)/25;
  const y = (event.clientY-top-height/2)/25;
  card.style.transform = `rotateY(${x}deg) rotateX(${-y}deg)`;
});
card.addEventListener('pointerleave', reset);
card.addEventListener('pointercancel', reset);
enabled.addEventListener('change', reset);
