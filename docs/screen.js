const player = document.getElementById('player');
const films = Array.from(document.querySelectorAll('.film'));
function selectFilm(film, play) {
  const title = film.querySelector('strong').textContent;
  const slug = film.dataset.slug;
  if (player.dataset.selected !== slug) {
    player.pause();
    player.querySelectorAll('track').forEach(track => track.remove());
    player.src = film.href;
    player.poster = film.querySelector('img').src;
    player.dataset.selected = slug;
    player.parentElement.classList.toggle('portrait', ['brick-beat', 'inside-cale'].includes(slug));
    player.setAttribute('aria-label', title);
    if (slug === 'where-the-ice-went') {
      const track = document.createElement('track');
      Object.assign(track, {kind:'captions', label:'English', srclang:'en', src:'films/where-the-ice-went.vtt'});
      player.append(track);
    }
    for (const item of films) {
      if (item === film) item.setAttribute('aria-current', 'true');
      else item.removeAttribute('aria-current');
    }
    document.getElementById('genre').textContent = film.querySelector('small').textContent + ' · ' + film.querySelector('time').textContent;
    document.getElementById('title').textContent = title;
    document.getElementById('synopsis').textContent = film.dataset.description;
    document.title = title + ' · C.A.L.E.';
  }
  if (play) player.play().catch(() => {});
}
function selectLocation() {
  selectFilm(films.find(film => '#' + film.dataset.slug === location.hash) || films[0], false);
}
for (const film of films) {
  film.addEventListener('click', event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button !== 0) return;
    event.preventDefault();
    const hash = '#' + film.dataset.slug;
    if (location.hash !== hash) history.pushState(null, '', hash);
    selectFilm(film, true);
    if (matchMedia('(max-width:830px)').matches) player.scrollIntoView({block:'nearest'});
  });
}
window.addEventListener('hashchange', selectLocation);
window.addEventListener('popstate', selectLocation);
selectLocation();
