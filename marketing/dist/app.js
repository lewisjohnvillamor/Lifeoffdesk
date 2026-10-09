'use strict';
const path = document.querySelector('#walk-path');
const reveal = document.querySelector('#reveal-path');
const walker = document.querySelector('#walker');
const toggle = document.querySelector('#walk-toggle');
const reset = document.querySelector('#walk-reset');
const title = document.querySelector('#walk-state-title');
const description = document.querySelector('#walk-description');
const announcement = document.querySelector('#walk-announcement');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let progress = 0, running = false, frame = 0, previous = 0, stage = -1;
const length = path.getTotalLength();
function paint() {
  path.style.strokeDashoffset = 100 - progress;
  reveal.style.strokeDashoffset = 100 - progress;
  const point = path.getPointAtLength(length * progress / 100);
  walker.setAttribute('transform', `translate(${point.x} ${point.y})`);
  document.querySelector('#stop-corner').classList.toggle('reached', progress >= 40);
  document.querySelector('#stop-park').classList.toggle('reached', progress >= 100);
  const nextStage = progress >= 100 ? 3 : progress >= 40 ? 2 : progress > 0 ? 1 : 0;
  if (stage !== nextStage) {
    stage = nextStage;
    const states = [
      ['Every adventure starts somewhere.', 'A little of the map is yours. Start walking to see what’s around the corner.'],
      ['A few steps, a fresh perspective.', 'As the simulated walk moves forward, a little more of the neighborhood appears.'],
      ['Hello, new corner.', 'A small detour opens up another part of your map. There’s a little green space ahead.'],
      ['A little adventure, just like that.', 'You’ve reached the end of this illustrated walk. In the app, your map grows through actual movement.']
    ];
    title.textContent = states[stage][0]; description.textContent = states[stage][1];
    if (progress) announcement.textContent = states[stage][0];
  }
}
function stop() { running = false; cancelAnimationFrame(frame); previous = 0; }
function tick(now) {
  if (!running) return;
  if (previous) progress = Math.min(100, progress + Math.min(now - previous, 100) / 140);
  previous = now; paint();
  if (progress >= 100) {stop();toggle.textContent = 'Walk again';return;}
  frame = requestAnimationFrame(tick);
}
function clearWalk() {stop();progress=0;stage=-1;paint();toggle.textContent='Start the demo walk';announcement.textContent='Demo walk reset.';}
toggle.addEventListener('click', () => {
  if (progress >= 100) clearWalk();
  if (reducedMotion.matches) {
    progress = Math.min(100, progress + 50);paint();toggle.textContent=progress>=100?'Walk again':'Continue the demo walk';return;
  }
  if (running) {stop();toggle.textContent='Continue the demo walk';announcement.textContent='Demo walk paused.';}
  else {running=true;toggle.textContent='Pause the demo walk';frame=requestAnimationFrame(tick);}
});
reset.addEventListener('click', clearWalk);
function pauseForVisibility() {if (running) {stop();toggle.textContent='Continue the demo walk';}}
document.addEventListener('visibilitychange',()=>{if(document.hidden)pauseForVisibility();});
reducedMotion.addEventListener('change',pauseForVisibility);
if ('IntersectionObserver' in window) new IntersectionObserver(entries=>{if(!entries[0].isIntersecting)pauseForVisibility();},{threshold:0.05}).observe(document.querySelector('#demo-map'));
paint();
const examples = {
  park:['“May 30 minutes ako. Gusto ko ng quiet na park.”','30 minutes. A park. A quieter moment.','The app uses your preferences to search its local catalog. Quietness needs supporting information; it won’t simply guess.'],
  coffee:['“Coffee break muna. May café ba nearby?”','A coffee stop, close to home.','The planned experience matches your café preference to catalog records and labels straight-line distance. Opening hours stay unverified unless supported.'],
  new:['“Somewhere new naman, kahit malapit lang.”','A familiar area. A different corner.','Adaptive suggestions are planned to use your recorded exploration to find something new. A suggestion is not a verified walking route.']
};
document.querySelectorAll('[data-example]').forEach(button=>button.addEventListener('click',()=>{
  document.querySelectorAll('[data-example]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));
  const [prompt,heading,reply]=examples[button.dataset.example];
  document.querySelector('#sample-prompt').textContent=prompt;
  document.querySelector('#sample-title').textContent=heading;
  document.querySelector('#sample-reply').textContent=reply;
}));
document.querySelector('#year').textContent=new Date().getFullYear();
