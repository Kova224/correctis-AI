// =============================================================================
// Page d'achat de crédits Correctis (option B, 15/10/2026)
// =============================================================================
// Google Play interdit de vendre des contenus numériques dans l'app sans son
// propre système de paiement. Les crédits s'achètent donc ici, par CinetPay
// (Mobile Money ou carte en FCFA), avec le même compte que dans l'app.
//
// Parcours : connexion → pays de facturation → pack (pour moi / pour mon
// école) → moyen de paiement + numéro → page CinetPay → retour ici
// (?order=<id>) → statut de la commande.
//
// Tout passe par les RPC du serveur (create_payment_order, ...) et l'Edge
// Function cinetpay-init-payment : la page ne fixe ni prix ni devise.
// =============================================================================
(function () {
  'use strict';

  var cfg = window.CORRECTIS_CONFIG;
  var sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, {
    auth: { flowType: 'pkce', persistSession: true, detectSessionInUrl: true },
  });

  // ── Données de référence (miroir de lib/models/billing.dart et de
  //    OPERATORS_BY_COUNTRY dans cinetpay-init-payment) ──
  var COUNTRIES = [
    { code: 'BJ', name: 'Bénin', dial: '229', min: 8, max: 10, ops: ['MTN', 'MOOV'] },
    { code: 'BF', name: 'Burkina Faso', dial: '226', min: 8, max: 8, ops: ['OM', 'MOOV', 'WAVE'] },
    { code: 'CI', name: "Côte d'Ivoire", dial: '225', min: 10, max: 10, ops: ['OM', 'MTN', 'MOOV', 'WAVE'] },
    { code: 'GN', name: 'Guinée', dial: '224', min: 8, max: 9, ops: ['OM', 'MTN'] },
    { code: 'ML', name: 'Mali', dial: '223', min: 8, max: 8, ops: ['OM', 'MOOV'] },
    { code: 'NE', name: 'Niger', dial: '227', min: 8, max: 8, ops: ['AIRTEL', 'MOOV'] },
    { code: 'SN', name: 'Sénégal', dial: '221', min: 9, max: 9, ops: ['OM', 'WAVE', 'FREE'] },
    { code: 'TG', name: 'Togo', dial: '228', min: 8, max: 8, ops: ['MOOV', 'TMONEY'] },
  ];
  var METHOD_LABELS = {
    OM: 'Orange Money',
    MTN: 'MTN Mobile Money',
    WAVE: 'Wave',
    MOOV: 'Moov Money',
    AIRTEL: 'Airtel Money',
    FREE: 'Free Money',
    TMONEY: 'T-Money',
    CARD: 'Carte bancaire',
  };
  var PACK_HINTS = {
    micro: '1 classe, petit devoir',
    solo_s: '1 classe, 1 devoir',
    solo_m: '2 à 3 classes',
    solo_l: 'Un trimestre complet',
    solo_xl: 'Plusieurs niveaux',
    solo_max: 'Université, formation',
    estab_small: 'Petit collège ou lycée',
    estab_mid: 'Lycée moyen',
    estab_large: 'Grand établissement',
    estab_uni: 'Université, institut',
    estab_group: "Groupe d'établissements",
  };
  var LAST_ORDER_KEY = 'correctis_last_order';
  var LAST_PHONE_KEY = 'correctis_last_phone';

  var state = {
    ctx: null,          // get_my_purchase_context
    packs: [],          // credit_packs actifs
    target: null,       // 'user' | 'establishment'
    schoolId: null,
    pack: null,
    method: null,
    busy: false,
  };

  // ── Utilitaires ──
  function $(id) { return document.getElementById(id); }
  function show(id, visible) { $(id).hidden = !visible; }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function store(key, value) {
    try { if (value == null) localStorage.removeItem(key); else localStorage.setItem(key, value); } catch (e) { /* stockage indisponible */ }
  }
  function load(key) {
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }
  function thousands(n) {
    return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  }
  function currencyLabel(c) { return c === 'XOF' ? 'FCFA' : c; }
  function money(amount, currency) { return thousands(amount) + ' ' + currencyLabel(currency); }
  function country() {
    var code = state.ctx && state.ctx.billing_country;
    for (var i = 0; i < COUNTRIES.length; i++) if (COUNTRIES[i].code === code) return COUNTRIES[i];
    return null;
  }
  function views(name) {
    ['loading', 'login', 'shop', 'return'].forEach(function (v) { show('view-' + v, v === name); });
  }

  // Message lisible pour une erreur serveur (RPC ou Edge Function).
  function readableError(err, fallback) {
    var msg = (err && (err.message || err.error || String(err))) || '';
    if (/BILLING_COUNTRY_REQUIRED/.test(msg)) return 'Choisissez d\'abord votre pays de facturation.';
    if (/BILLING_COUNTRY_LOCKED/.test(msg)) return 'Le pays ne peut plus être changé après un premier paiement.';
    if (/ADMIN_NO_SOLO_PACK/.test(msg)) return 'Un compte administrateur achète des packs pour son école.';
    if (/NOT_SCHOOL_ADMIN/.test(msg)) return 'Seul un administrateur de l\'école peut acheter pour elle.';
    if (/COUNTRY_NOT_SUPPORTED/.test(msg)) return 'Ce pays n\'est pas encore couvert.';
    if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) return 'Connexion impossible. Vérifiez votre réseau et réessayez.';
    return msg || fallback || 'Une erreur est survenue. Réessayez.';
  }
  async function functionError(error) {
    // FunctionsHttpError : le corps JSON { error } est dans error.context.
    try {
      if (error && error.context && typeof error.context.json === 'function') {
        var body = await error.context.json();
        if (body && body.error) return body.error;
      }
    } catch (e) { /* corps illisible */ }
    return readableError(error, 'Le paiement n\'a pas pu être lancé.');
  }

  // ── Démarrage ──
  async function start() {
    $('support-link').href = 'mailto:' + cfg.supportEmail;
    $('support-link').textContent = cfg.supportEmail;
    bindLogin();
    bindShop();

    var params = new URLSearchParams(location.search);
    var orderId = params.get('order');

    var res = await sb.auth.getSession();
    var session = res && res.data && res.data.session;
    if (!session) {
      views('login');
      return;
    }
    await onSignedIn(session, orderId);
  }

  async function onSignedIn(session, orderId) {
    $('account-email').textContent = session.user.email || '';
    show('account', true);
    if (orderId) {
      await showReturn(orderId);
      return;
    }
    await openShop();
  }

  // ── Connexion ──
  function bindLogin() {
    $('login-form').addEventListener('submit', async function (ev) {
      ev.preventDefault();
      var email = $('login-email').value.trim();
      var password = $('login-password').value;
      show('login-error', false);
      if (!email || !password) {
        $('login-error').textContent = 'Saisissez votre e-mail et votre mot de passe.';
        show('login-error', true);
        return;
      }
      $('login-submit').disabled = true;
      var r = await sb.auth.signInWithPassword({ email: email, password: password });
      $('login-submit').disabled = false;
      if (r.error) {
        $('login-error').textContent = /Invalid login/i.test(r.error.message)
          ? 'E-mail ou mot de passe incorrect.'
          : /Email not confirmed/i.test(r.error.message)
            ? 'Confirmez d\'abord votre adresse e-mail (lien reçu à l\'inscription).'
            : readableError(r.error);
        show('login-error', true);
        return;
      }
      var orderId = new URLSearchParams(location.search).get('order');
      await onSignedIn(r.data.session, orderId);
    });

    $('login-google').addEventListener('click', async function () {
      await sb.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: location.origin + location.pathname + location.search },
      });
    });

    $('login-forgot').addEventListener('click', async function () {
      var email = $('login-email').value.trim();
      show('login-error', false);
      if (!email) {
        $('login-error').textContent = 'Saisissez d\'abord votre adresse e-mail.';
        show('login-error', true);
        return;
      }
      await sb.auth.resetPasswordForEmail(email);
      $('login-error').textContent = 'Si ce compte existe, un e-mail de réinitialisation vient d\'être envoyé.';
      show('login-error', true);
    });

    $('logout').addEventListener('click', async function () {
      await sb.auth.signOut();
      store(LAST_ORDER_KEY, null);
      location.href = location.pathname;
    });
  }

  // ── Boutique ──
  async function openShop() {
    views('loading');
    var ctxRes = await sb.rpc('get_my_purchase_context');
    if (ctxRes.error) {
      views('login');
      $('login-error').textContent = readableError(ctxRes.error, 'Impossible de charger votre compte.');
      show('login-error', true);
      return;
    }
    state.ctx = ctxRes.data;

    var packsRes = await sb
      .from('credit_packs')
      .select('code, scope, name, copies_max, price_xof, price_gnf, marketing_label, display_order')
      .eq('is_active', true)
      .order('display_order');
    state.packs = (packsRes.data || []).filter(function (p) { return p.code !== 'discovery'; });

    var targets = [];
    if (state.ctx.account_type !== 'admin') targets.push('user');
    if ((state.ctx.admin_schools || []).length) targets.push('establishment');
    state.target = targets[0] || null;
    state.schoolId = (state.ctx.admin_schools || [])[0] ? state.ctx.admin_schools[0].id : null;

    views('shop');
    show('no-target', targets.length === 0);
    show('step-country', targets.length > 0);
    show('target-switch', targets.length > 1);
    renderCountry();
    renderSchools();
    renderPacks();
    renderMethods();
  }

  function renderCountry() {
    var c = country();
    var sel = $('country-select');
    if (!sel.options.length) {
      sel.appendChild(new Option('Choisir le pays…', ''));
      COUNTRIES.forEach(function (x) { sel.appendChild(new Option(x.name, x.code)); });
    }
    show('country-fixed', !!c);
    show('country-pick', !c);
    if (c) {
      $('country-name').textContent = c.name;
      $('country-currency').textContent = c.code === 'GN' ? 'francs guinéens (GNF)' : 'FCFA (XOF)';
      show('country-change', !!state.ctx.can_change_country);
      show('country-locked', !state.ctx.can_change_country);
      $('phone-prefix').textContent = '+' + c.dial;
    }
    var ready = !!c && !!state.target;
    show('step-pack', ready);
    show('step-pay', ready && !!state.pack);
  }

  function renderSchools() {
    var schools = state.ctx.admin_schools || [];
    var sel = $('school-select');
    sel.innerHTML = '';
    schools.forEach(function (s) { sel.appendChild(new Option(s.name, s.id)); });
    if (state.schoolId) sel.value = state.schoolId;
    show('school-pick', state.target === 'establishment' && schools.length > 1);
    var tabs = $('target-switch').querySelectorAll('button');
    tabs.forEach(function (b) { b.setAttribute('aria-selected', String(b.dataset.target === state.target)); });
  }

  function renderPacks() {
    var box = $('packs');
    box.innerHTML = '';
    box.className = 'packs ' + (state.target || '');
    var c = country();
    if (!c || !state.target) return;
    var currency = c.code === 'GN' ? 'GNF' : 'XOF';
    var scope = state.target === 'establishment' ? 'establishment' : 'solo';
    state.packs.filter(function (p) { return p.scope === scope; }).forEach(function (p) {
      var price = currency === 'GNF' ? p.price_gnf : p.price_xof;
      if (!price) return;
      var b = el('button', 'pack');
      b.type = 'button';
      b.setAttribute('role', 'radio');
      b.setAttribute('aria-checked', String(state.pack && state.pack.code === p.code));
      if (p.marketing_label) b.appendChild(el('span', 'tag', p.marketing_label));
      b.appendChild(el('div', 'name', p.name));
      b.appendChild(el('div', 'credits', p.copies_max + ' crédits'));
      b.appendChild(el('div', 'price', money(price, currency)));
      b.appendChild(el('div', 'per', money(price / p.copies_max, currency) + ' / copie'));
      if (PACK_HINTS[p.code]) b.appendChild(el('div', 'hint', PACK_HINTS[p.code]));
      b.addEventListener('click', function () {
        state.pack = { code: p.code, name: p.name, price: price, currency: currency, credits: p.copies_max };
        renderPacks();
        renderCountry();
        updatePayButton();
        $('step-pay').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      });
      box.appendChild(b);
    });
  }

  function renderMethods() {
    var c = country();
    var box = $('methods');
    box.innerHTML = '';
    if (!c) return;
    var list = c.ops.slice();
    var cardOk = !!cfg.cardEnabled;
    if (cardOk) list.push('CARD');
    if (list.indexOf(state.method) < 0) state.method = list[0];
    list.forEach(function (code) {
      var b = el('button', 'method', METHOD_LABELS[code] || code);
      b.type = 'button';
      b.setAttribute('role', 'radio');
      b.setAttribute('aria-checked', String(state.method === code));
      b.addEventListener('click', function () {
        state.method = code;
        renderMethods();
        updatePayButton();
      });
      box.appendChild(b);
    });
    show('card-note', !cardOk);
    var isCard = state.method === 'CARD';
    $('phone-label').textContent = isCard ? 'Votre numéro de téléphone' : 'Numéro de téléphone du compte de paiement';
    $('phone-hint').textContent = isCard
      ? 'CinetPay le demande pour la carte. Vous saisirez les informations de la carte sur leur page sécurisée.'
      : 'Vous recevrez la demande de confirmation sur ce numéro.';
    if (!$('phone').value) {
      var last = load(LAST_PHONE_KEY);
      if (last && last.indexOf(c.dial + ':') === 0) $('phone').value = last.split(':')[1];
    }
  }

  function phoneProblem() {
    var c = country();
    if (!c) return 'Choisissez votre pays.';
    var digits = $('phone').value.replace(/\D/g, '');
    if (digits.indexOf('00' + c.dial) === 0) digits = digits.slice(c.dial.length + 2);
    else if (digits.indexOf(c.dial) === 0 && digits.length >= c.dial.length + c.min) digits = digits.slice(c.dial.length);
    if (!digits) return 'Saisissez le numéro du compte de paiement.';
    if (digits.length < c.min || digits.length > c.max) {
      var range = c.min === c.max ? c.min + ' chiffres' : c.min + ' à ' + c.max + ' chiffres';
      return 'Numéro invalide : ' + range + ' après +' + c.dial + '.';
    }
    if (c.code === 'GN' && digits.charAt(0) !== '6') return 'Un numéro mobile guinéen commence par 6.';
    return null;
  }
  function phoneDigits() {
    var c = country();
    var digits = $('phone').value.replace(/\D/g, '');
    if (digits.indexOf('00' + c.dial) === 0) digits = digits.slice(c.dial.length + 2);
    else if (digits.indexOf(c.dial) === 0 && digits.length >= c.dial.length + c.min) digits = digits.slice(c.dial.length);
    return digits;
  }

  function updatePayButton() {
    var ok = !!state.pack && !!state.method && !phoneProblem() && !state.busy;
    $('pay').disabled = !ok;
    $('pay').textContent = state.busy
      ? 'Redirection vers CinetPay…'
      : state.pack ? 'Payer ' + money(state.pack.price, state.pack.currency) : 'Payer';
  }

  function bindShop() {
    $('country-save').addEventListener('click', async function () {
      var code = $('country-select').value;
      if (!code) return;
      var name = (COUNTRIES.filter(function (x) { return x.code === code; })[0] || {}).name;
      if (!window.confirm('Pays de facturation : ' + name + '.\nIl ne pourra plus être changé après votre premier paiement. Continuer ?')) return;
      $('country-save').disabled = true;
      var r = await sb.rpc('set_my_billing_country', { p_country: code });
      $('country-save').disabled = false;
      if (r.error) { window.alert(readableError(r.error)); return; }
      state.ctx.billing_country = code;
      state.pack = null;
      $('phone').value = '';
      renderCountry();
      renderPacks();
      renderMethods();
      updatePayButton();
    });

    $('country-change').addEventListener('click', function () {
      show('country-fixed', false);
      show('country-pick', true);
      $('country-select').value = state.ctx.billing_country || '';
    });

    $('target-switch').addEventListener('click', function (ev) {
      var t = ev.target.closest('button');
      if (!t) return;
      state.target = t.dataset.target;
      state.pack = null;
      renderSchools();
      renderPacks();
      renderCountry();
      updatePayButton();
    });

    $('school-select').addEventListener('change', function () { state.schoolId = this.value; });
    $('phone').addEventListener('input', function () { show('pay-error', false); updatePayButton(); });

    $('pay').addEventListener('click', pay);
  }

  async function pay() {
    var problem = phoneProblem();
    if (problem) { $('pay-error').textContent = problem; show('pay-error', true); return; }
    if (!state.pack || state.busy) return;
    var c = country();
    var phone = '+' + c.dial + phoneDigits();
    state.busy = true;
    show('pay-error', false);
    updatePayButton();
    try {
      var order = await sb.rpc('create_payment_order', {
        p_pack_code: state.pack.code,
        p_target_kind: state.target,
        p_establishment_id: state.target === 'establishment' ? state.schoolId : null,
      });
      if (order.error) throw new Error(readableError(order.error));
      var row = Array.isArray(order.data) ? order.data[0] : order.data;
      if (!row || !row.out_order_id) throw new Error('La commande n\'a pas pu être créée.');

      var init = await sb.functions.invoke('cinetpay-init-payment', {
        body: { order_id: row.out_order_id, payment_method: state.method, phone_number: phone },
      });
      if (init.error) throw new Error(await functionError(init.error));
      var url = init.data && init.data.payment_url;
      if (!url) throw new Error('CinetPay n\'a pas renvoyé de page de paiement.');

      store(LAST_ORDER_KEY, row.out_order_id);
      store(LAST_PHONE_KEY, c.dial + ':' + phoneDigits());
      location.href = url;
    } catch (e) {
      state.busy = false;
      $('pay-error').textContent = e.message || 'Le paiement n\'a pas pu être lancé.';
      show('pay-error', true);
      updatePayButton();
    }
  }

  // ── Retour de CinetPay ──
  async function showReturn(orderId) {
    views('return');
    var actions = $('result-actions');
    actions.innerHTML = '';
    if (!orderId) { await openShop(); return; }

    var attempts = 0;
    var maxAttempts = 40; // ~2 minutes
    async function poll() {
      attempts++;
      var r = await sb.rpc('get_my_payment_order', { p_order_id: orderId });
      var row = r.data && (Array.isArray(r.data) ? r.data[0] : r.data);
      if (!row) {
        setResult('ko', 'Commande introuvable',
          'Cette commande n\'est pas liée au compte connecté. Vérifiez que vous utilisez le même compte que pour le paiement.');
        addAction('Retour aux packs', true, backToShop);
        return;
      }
      if (row.out_status === 'completed') {
        store(LAST_ORDER_KEY, null);
        var who = row.out_target_kind === 'establishment' ? 'à votre école' : 'à votre compte';
        setResult('ok', 'Paiement confirmé',
          row.out_credits + ' crédits (pack ' + row.out_pack_name + ', ' + money(row.out_amount, row.out_currency) +
          ') ont été ajoutés ' + who + '. Ouvrez l\'application Correctis pour les utiliser.');
        addAction('Acheter un autre pack', false, backToShop);
        return;
      }
      if (row.out_status === 'failed') {
        store(LAST_ORDER_KEY, null);
        setResult('ko', 'Paiement non abouti',
          'Le paiement a été refusé ou annulé' + (row.out_failure_reason ? ' (' + row.out_failure_reason + ')' : '') +
          '. Aucun montant n\'a été débité pour cette commande.');
        addAction('Réessayer', true, backToShop);
        return;
      }
      if (attempts >= maxAttempts) {
        setResult('pending-still', 'Paiement en attente de confirmation',
          'Si vous avez validé le paiement sur votre téléphone, les crédits arriveront dès que CinetPay l\'aura confirmé. Vous pouvez fermer cette page.');
        addAction('Vérifier à nouveau', true, function () { attempts = 0; actions.innerHTML = ''; setResult('pending'); poll(); });
        addAction('Retour aux packs', false, backToShop);
        return;
      }
      setTimeout(poll, 3000);
    }
    setResult('pending');
    poll();
  }

  function setResult(kind, title, text) {
    var icon = $('result-icon');
    icon.className = 'result-icon ' + (kind === 'ok' ? 'ok' : kind === 'ko' ? 'ko' : kind === 'pending-still' ? 'ko' : 'pending');
    $('result-title').textContent = title || 'Vérification du paiement…';
    $('result-text').textContent = text || 'Nous attendons la confirmation de CinetPay. Cela prend en général moins d\'une minute.';
  }
  function addAction(label, primary, fn) {
    var b = el('button', 'btn ' + (primary ? 'primary' : 'outline'), label);
    b.type = 'button';
    b.addEventListener('click', fn);
    $('result-actions').appendChild(b);
  }
  function backToShop() {
    history.replaceState(null, '', location.pathname);
    state.pack = null;
    state.busy = false;
    openShop();
  }

  start().catch(function (e) {
    views('login');
    $('login-error').textContent = readableError(e);
    show('login-error', true);
  });
})();
