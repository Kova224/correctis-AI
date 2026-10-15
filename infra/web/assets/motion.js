// =============================================================================
// Correctis — mouvement du site (voir motion.css pour les jetons et les règles)
// Tout est progressif : sans JavaScript ou avec « réduire les animations »,
// le contenu s'affiche directement, sans effet.
// =============================================================================
(function () {
  'use strict';

  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var finePointer = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  var hasIO = 'IntersectionObserver' in window;

  // ── En-tête : resserré au défilement + trait d'encre de progression ──
  var head = document.querySelector('.site-head');
  if (head) {
    var bar = document.createElement('span');
    bar.className = 'progress';
    bar.setAttribute('aria-hidden', 'true');
    head.appendChild(bar);
    var ticking = false;
    var onScroll = function () {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(function () {
        var y = window.scrollY || window.pageYOffset;
        var max = document.documentElement.scrollHeight - window.innerHeight;
        head.classList.toggle('scrolled', y > 8);
        head.style.setProperty('--progress', max > 0 ? Math.min(1, y / max).toFixed(4) : '0');
        ticking = false;
      });
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
    onScroll();
  }

  // ── Révélations au défilement ──
  document.querySelectorAll('[data-stagger]').forEach(function (group) {
    Array.prototype.forEach.call(group.children, function (child, i) {
      child.setAttribute('data-reveal', '');
      child.style.setProperty('--i', String(i));
    });
  });
  var revealables = document.querySelectorAll('[data-reveal], .pen-line');
  if (reduce || !hasIO) {
    revealables.forEach(function (el) { el.classList.add('is-in'); });
  } else {
    // Un titre masqué par clip-path a une surface visible nulle : on observe
    // alors son parent et on révèle le titre quand le parent arrive.
    var targets = new Map();
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        (targets.get(e.target) || []).forEach(function (el) { el.classList.add('is-in'); });
        io.unobserve(e.target);
      });
    }, { threshold: 0.15, rootMargin: '0px 0px -8% 0px' });
    revealables.forEach(function (el) {
      var watch = el.tagName === 'H2' ? el.parentElement : el;
      if (!targets.has(watch)) targets.set(watch, []);
      targets.get(watch).push(el);
      io.observe(watch);
    });
  }

  // ── Étapes : le trait se trace et chaque étape reçoit sa coche ──
  var steps = document.querySelectorAll('.steps li');
  steps.forEach(function (li, i) {
    li.style.setProperty('--i', String(i));
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'step-tick');
    svg.setAttribute('viewBox', '0 0 30 24');
    svg.setAttribute('aria-hidden', 'true');
    var p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    p.setAttribute('d', 'M3 13 L11 20 L27 4');
    p.setAttribute('pathLength', '1');
    svg.appendChild(p);
    li.appendChild(svg);
  });
  if (steps.length) {
    if (reduce || !hasIO) {
      steps.forEach(function (li) { li.classList.add('reached'); });
    } else {
      var sio = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) { e.target.classList.add('reached'); sio.unobserve(e.target); }
        });
      }, { threshold: 0.6 });
      steps.forEach(function (li) { sio.observe(li); });
    }
  }

  // ── Navigation : le lien de la section affichée est souligné ──
  var links = Array.prototype.filter.call(document.querySelectorAll('.nav a[href^="#"]'), function (a) {
    return document.getElementById(a.getAttribute('href').slice(1));
  });
  if (links.length && hasIO) {
    var current = null;
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) current = e.target.id;
      });
      links.forEach(function (a) { a.classList.toggle('is-active', a.getAttribute('href') === '#' + current); });
    }, { rootMargin: '-45% 0px -50% 0px' });
    links.forEach(function (a) { spy.observe(document.getElementById(a.getAttribute('href').slice(1))); });
  }

  // ── Héros : le scanner parcourt toute la copie ; légère inclinaison ──
  var copy = document.querySelector('.copy');
  if (copy) copy.style.setProperty('--scan-end', copy.offsetHeight + 'px');
  var tilt = document.querySelector('.copy-tilt');
  var hero = document.querySelector('.hero');
  if (tilt && hero && finePointer && !reduce) {
    hero.addEventListener('pointermove', function (e) {
      var r = tilt.getBoundingClientRect();
      var x = (e.clientX - (r.left + r.width / 2)) / r.width;
      var y = (e.clientY - (r.top + r.height / 2)) / r.height;
      tilt.style.setProperty('--ry', (Math.max(-1, Math.min(1, x)) * 4).toFixed(2) + 'deg');
      tilt.style.setProperty('--rx', (Math.max(-1, Math.min(1, -y)) * 3).toFixed(2) + 'deg');
    });
    hero.addEventListener('pointerleave', function () {
      tilt.style.setProperty('--ry', '0deg');
      tilt.style.setProperty('--rx', '0deg');
    });
  }

  // ── Tarifs : la pastille glisse vers la monnaie choisie ──
  var cur = document.querySelector('.currency');
  if (cur) {
    var pill = document.createElement('span');
    pill.className = 'pill';
    pill.setAttribute('aria-hidden', 'true');
    cur.insertBefore(pill, cur.firstChild);
    var place = function (instant) {
      var on = cur.querySelector('button[aria-pressed="true"]');
      if (!on) return;
      if (instant) pill.style.transition = 'none';
      pill.style.width = on.offsetWidth + 'px';
      pill.style.transform = 'translateX(' + on.offsetLeft + 'px)';
      if (instant) { void pill.offsetWidth; pill.style.transition = ''; }
    };
    place(true);
    cur.addEventListener('click', function () { place(false); });
    window.addEventListener('resize', function () { place(true); });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { place(true); });
  }

  // ── Questions : ouverture et fermeture en douceur ──
  if (!reduce && Element.prototype.animate) {
    document.querySelectorAll('.faq details').forEach(function (d) {
      var summary = d.querySelector('summary');
      var anim = null;
      summary.addEventListener('click', function (ev) {
        ev.preventDefault();
        if (anim) anim.cancel();
        var start = d.offsetHeight;
        if (d.open) {
          var end = summary.offsetHeight;
          d.classList.add('closing');
          anim = d.animate({ height: [start + 'px', end + 'px'] }, { duration: 260, easing: 'cubic-bezier(.65,0,.35,1)' });
          anim.onfinish = function () { d.open = false; d.classList.remove('closing'); anim = null; };
        } else {
          d.style.height = start + 'px';
          d.open = true;
          var full = d.scrollHeight;
          d.style.height = '';
          anim = d.animate({ height: [start + 'px', full + 'px'] }, { duration: 320, easing: 'cubic-bezier(.2,.8,.2,1)' });
          anim.onfinish = function () { anim = null; };
        }
      });
    });
  }
})();
