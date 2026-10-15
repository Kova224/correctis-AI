// Correctis — scripts du site vitrine (menu mobile, tableau des tarifs).
(function () {
  'use strict';

  // ── Menu mobile ──
  var btn = document.querySelector('.menu-btn');
  var nav = document.getElementById('nav');
  if (btn && nav) {
    btn.addEventListener('click', function () {
      var open = nav.classList.toggle('open');
      btn.setAttribute('aria-expanded', String(open));
    });
    nav.addEventListener('click', function (e) {
      if (e.target.closest('a')) { nav.classList.remove('open'); btn.setAttribute('aria-expanded', 'false'); }
    });
  }

  // ── Tarifs (grille v5, septembre 2026) ──
  // Les prix officiels sont en base (table credit_packs) ; cette copie sert
  // uniquement à l'affichage du site. À mettre à jour si la grille change.
  var SOLO = [
    { name: 'Micro', copies: 15, xof: 450, gnf: 7000, hint: '1 classe, petit devoir' },
    { name: 'Solo S', copies: 30, xof: 875, gnf: 13500, hint: '1 classe, 1 devoir' },
    { name: 'Solo M', copies: 80, xof: 2300, gnf: 35500, hint: '2 à 3 classes', pop: true },
    { name: 'Solo L', copies: 150, xof: 4250, gnf: 65500, hint: 'Un trimestre complet' },
    { name: 'Solo XL', copies: 300, xof: 8400, gnf: 130000, hint: 'Plusieurs niveaux' },
    { name: 'Solo MAX', copies: 500, xof: 14000, gnf: 216500, hint: 'Université, formation' },
  ];
  var SCHOOL = [
    { name: 'Petit', copies: 200, xof: 6000, gnf: 93000, hint: 'Petit collège ou lycée' },
    { name: 'Moyen', copies: 500, xof: 14500, gnf: 227000, hint: 'Lycée moyen' },
    { name: 'Grand lycée', copies: 1000, xof: 28500, gnf: 445000, hint: 'Grand établissement' },
    { name: 'Université', copies: 2500, xof: 70500, gnf: 1095000, hint: 'Université, institut' },
    { name: 'Groupe', copies: 5000, xof: 140000, gnf: 2165000, hint: "Groupe d'établissements" },
  ];
  var NOTES = {
    XOF: "Bénin, Burkina Faso, Côte d'Ivoire, Mali, Niger, Sénégal et Togo. Paiement par Mobile Money ou carte bancaire.",
    GNF: 'Guinée. Paiement par Orange Money ou MTN Mobile Money.',
  };

  function money(n, cur) {
    var s = String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    return s + ' ' + (cur === 'XOF' ? 'F CFA' : 'GNF');
  }
  function fill(tableId, packs, cur) {
    var body = document.querySelector('#' + tableId + ' tbody');
    if (!body) return;
    body.innerHTML = '';
    packs.forEach(function (p) {
      var price = cur === 'XOF' ? p.xof : p.gnf;
      var tr = document.createElement('tr');
      var td1 = document.createElement('td');
      var name = document.createElement('strong');
      name.textContent = p.name;
      td1.appendChild(name);
      if (p.pop) { var pop = document.createElement('span'); pop.className = 'pop'; pop.textContent = 'le plus choisi'; td1.appendChild(pop); }
      var hint = document.createElement('span'); hint.className = 'hint'; hint.textContent = p.hint; td1.appendChild(hint);
      var td2 = document.createElement('td'); td2.className = 'num'; td2.textContent = String(p.copies).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
      var td3 = document.createElement('td'); td3.className = 'num';
      var strong = document.createElement('strong'); strong.textContent = money(price, cur); td3.appendChild(strong);
      var per = document.createElement('span'); per.className = 'hint'; per.textContent = money(price / p.copies, cur) + ' la copie'; td3.appendChild(per);
      tr.appendChild(td1); tr.appendChild(td2); tr.appendChild(td3);
      body.appendChild(tr);
    });
  }
  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var shown = null;

  // Les prix « roulent » de l'ancienne à la nouvelle monnaie (≈ 0,5 s).
  function tween(tableId, packs, from, to) {
    var cells = document.querySelectorAll('#' + tableId + ' td.num strong');
    var start = null;
    var dur = 520;
    function frame(t) {
      if (start === null) start = t;
      var k = Math.min(1, (t - start) / dur);
      var e = 1 - Math.pow(1 - k, 3);
      cells.forEach(function (cell, i) {
        var a = from === 'XOF' ? packs[i].xof : packs[i].gnf;
        var b = to === 'XOF' ? packs[i].xof : packs[i].gnf;
        cell.textContent = money(a + (b - a) * e, k < 1 && e < .5 ? from : to);
      });
      if (k < 1) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  }

  function setCurrency(cur) {
    var previous = shown;
    shown = cur;
    fill('prices-solo', SOLO, cur);
    fill('prices-school', SCHOOL, cur);
    if (previous && previous !== cur && !reduceMotion) {
      tween('prices-solo', SOLO, previous, cur);
      tween('prices-school', SCHOOL, previous, cur);
    }
    var note = document.getElementById('currency-note');
    if (note) note.textContent = NOTES[cur];
    document.querySelectorAll('.currency button').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.cur === cur));
    });
    try { localStorage.setItem('correctis_currency', cur); } catch (e) { /* stockage indisponible */ }
  }
  if (document.getElementById('prices-solo')) {
    var saved = null;
    try { saved = localStorage.getItem('correctis_currency'); } catch (e) { saved = null; }
    setCurrency(saved === 'GNF' ? 'GNF' : 'XOF');
    document.querySelectorAll('.currency button').forEach(function (b) {
      b.addEventListener('click', function () { setCurrency(b.dataset.cur); });
    });
  }
})();
