(() => {
  const hero = document.querySelector('.arc-hero-video');
  const toggle = document.querySelector('.arc-motion-toggle');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let userPaused = false;
  function hydrate(video) {
    const source = video.querySelector('source[data-src]');
    if (source && !source.hasAttribute('src')) {
      source.src = source.dataset.src;
      video.load();
    }
  }
  if (hero && toggle) {
    const update = () => {
      toggle.textContent = hero.paused ? 'PLAY VIDEO' : 'PAUSE VIDEO';
      toggle.setAttribute('aria-label', hero.paused ? 'Play background video' : 'Pause background video');
    };
    const play = () => { hydrate(hero); hero.muted = true; hero.play().catch(update); };
    toggle.hidden = false;
    hero.addEventListener('play', update);
    hero.addEventListener('pause', update);
    toggle.addEventListener('click', () => {
      userPaused = !hero.paused;
      if (hero.paused) play(); else hero.pause();
    });
    if (!reduced.matches && !navigator.connection?.saveData) play();
    reduced.addEventListener('change', () => { if (reduced.matches) { userPaused = true; hero.pause(); } });
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) hero.pause();
      else if (!userPaused && !reduced.matches && !navigator.connection?.saveData && !dialog?.open) play();
    });
  }
  const dialog = document.querySelector('.arc-film-dialog');
  if (!dialog) return;
  const film = dialog.querySelector('video');
  let opener;
  let resumeHero = false;
  document.querySelectorAll('[data-open-film]').forEach(button => button.addEventListener('click', () => {
    opener = button;
    resumeHero = hero && !hero.paused;
    hero?.pause();
    dialog.showModal();
    document.body.classList.add('arc-film-open');
    hydrate(film);
    film.play().catch(() => {});
  }));
  dialog.querySelector('.arc-film-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', e => { if (e.target === dialog) {
    const r = dialog.getBoundingClientRect();
    if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) dialog.close();
  }});
  dialog.addEventListener('close', () => {
    film.pause();
    document.body.classList.remove('arc-film-open');
    opener?.focus();
    if (resumeHero && !userPaused && !reduced.matches) hero.play().catch(() => {});
  });
})();
