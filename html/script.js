const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rsg-banking';
const $ = id => document.getElementById(id);
let state = null, busy = false;

const fmt = n => '$' + Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
let L = {};
// translate: t('key', a, b) replaces each %s in order
const t = (k, ...a) => { let i = 0; return String(L[k] ?? k).replace(/%s/g, () => a[i++] ?? ''); };
function applyI18n() {
  document.querySelectorAll('[data-i18n]').forEach(el => el.textContent = t(el.dataset.i18n));
  document.querySelectorAll('[data-i18n-ph]').forEach(el => el.placeholder = t(el.dataset.i18nPh));
  document.querySelectorAll('[data-i18n-title]').forEach(el => el.title = t(el.dataset.i18nTitle));
}
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));

function post(name, body = {}) {
  return fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).catch(() => {});
}

function postJson(name, body = {}) {
  return fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    .then(r => r.json()).catch(() => null);
}

// pure HTML dropdown: el = .dd container, options = [{ value, label }]
function setupDd(el, options, value, onChange) {
  const menu = el.querySelector('.dd-menu'), shown = el.querySelector('.dd-value');
  const pick = v => {
    const o = options.find(x => x.value === v) || options[0];
    el.dataset.value = o ? o.value : '';
    shown.textContent = o ? o.label : '';
    menu.querySelectorAll('.dd-opt').forEach(x => x.classList.toggle('sel', x.dataset.value === el.dataset.value));
  };
  menu.innerHTML = options.map(o => `<div class="dd-opt" data-value="${esc(o.value)}">${esc(o.label)}</div>`).join('');
  menu.querySelectorAll('.dd-opt').forEach(x => x.addEventListener('mousedown', e => {
    e.preventDefault(); e.stopPropagation(); pick(x.dataset.value); closeDds(); onChange && onChange(el.dataset.value);
  }));
  el.onmousedown = e => {
    if (e.target.closest('.dd-menu')) return;
    const open = !el.classList.contains('open'); closeDds();
    el.classList.toggle('open', open); menu.classList.toggle('hidden', !open);
  };
  pick(value);
}
function closeDds() { document.querySelectorAll('.dd').forEach(d => { d.classList.remove('open'); d.querySelector('.dd-menu').classList.add('hidden'); }); }
document.addEventListener('mousedown', e => { if (!e.target.closest('.dd')) closeDds(); });

function setTab(tab) {
  closeDds();
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
  ['vault', 'wire', 'branches', 'ledger', 'loans', 'lockbox', 'business'].forEach(t => $('tab-' + t).classList.toggle('hidden', t !== tab));
}

function calcFee() {
  if (!state) return;
  const a = parseFloat($('wireAmount').value) || 0;
  const fee = a > 0 ? Math.max(state.minFee, Math.round(a * state.feePercent) / 100) : 0;
  $('feeInfo').textContent = t('ui_fee_info', state.feePercent, fmt(fee), fmt(a + fee));
}

const TX = {
  deposit:  { icon: '&#8595;',  label: 'ui_tx_deposit',  sign: 1 },
  withdraw: { icon: '&#8593;',  label: 'ui_tx_withdraw', sign: -1 },
  wire_in:  { icon: '&#8618;',  label: 'ui_tx_wire_in',  sign: 1 },
  wire_out: { icon: '&#8617;',  label: 'ui_tx_wire_out', sign: -1 },
  opened:   { icon: '&#10022;', label: 'ui_tx_opened',   sign: -1 },
  loan:         { icon: '&#9878;',  label: 'ui_tx_loan',         sign: 1 },
  loan_payment: { icon: '&#9878;',  label: 'ui_tx_loan_payment', sign: -1 },
  loan_late:    { icon: '&#9888;',  label: 'ui_tx_loan_late',    sign: 0 },
  lockbox:      { icon: '&#128274;', label: 'ui_tx_lockbox',     sign: -1 },
  lockbox_up:   { icon: '&#128274;', label: 'ui_tx_lockbox_up',  sign: -1 },
  lockbox_rent: { icon: '&#128274;', label: 'ui_tx_lockbox_rent', sign: -1 },
  send_in:      { icon: '&#8601;',  label: 'ui_tx_send_in',      sign: 1 },
  send_out:     { icon: '&#8599;',  label: 'ui_tx_send_out',     sign: -1 },
  interest:     { icon: '&#37;',    label: 'ui_tx_interest',     sign: 1 },
  loan_default: { icon: '&#9888;',  label: 'ui_tx_loan_default', sign: 0 },
};

const fmtDate = ts => ts ? new Date(ts * 1000).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '';

function loanRepayInfo() {
  const l = state && state.loan; if (!l) return;
  const a = parseFloat($('loanAmount').value) || 0;
  $('loanRepayInfo').textContent = a > 0 ? t('ui_loan_repay_total', fmt(Math.round(a * (100 + l.interest)) / 100)) : '';
}

function renderLoans(l) {
  $('loansTabBtn').classList.toggle('hidden', !l);
  if (!l) return;
  $('creditLine').classList.toggle('hidden', l.score == null);
  if (l.score != null) $('creditLine').textContent = t('ui_credit_score', l.score);
  const a = l.active;
  $('loanActive').classList.toggle('hidden', !a);
  $('loanNew').classList.toggle('hidden', !!a || !!l.blocked);
  $('loanBlocked').classList.toggle('hidden', !!a || !l.blocked);
  if (a) {
    $('loanOwed').textContent = fmt(a.owed);
    const late = a.late || a.due < l.now;
    $('loanDue').textContent = late ? t('ui_loan_overdue') : t('ui_loan_due', fmtDate(a.due)) + ' · ' + t('ui_loan_borrowed', fmt(a.principal));
    $('loanDue').classList.toggle('late', late);
  } else if (l.blocked) {
    $('loanBlockedText').textContent = l.blocked === 'credit' ? t('ui_loan_credit', l.score) : l.blocked === 'age' ? t('ui_loan_age', l.minHours) : (l.elsewhere && l.elsewhere.length ? t('ui_loan_limit_at', l.elsewhere.join(', ')) : t('ui_loan_limit'));
  } else {
    $('loanTerms').textContent = t('ui_loan_terms', l.interest, l.termDays, fmt(l.min), fmt(l.max));
    loanRepayInfo();
  }
}

const itemImg = (b, it) => `<img class="item-img" src="${esc((b.imagePath || '') + it.image)}" onerror="this.style.visibility='hidden'">`;

function renderLockbox(b) {
  $('lockboxTabBtn').classList.toggle('hidden', !b);
  if (!b) return;
  const box = b.box;
  $('boxShop').classList.toggle('hidden', !!box);
  $('boxOwned').classList.toggle('hidden', !box);
  if (!box) {
    $('boxAccepts').textContent = t('ui_lockbox_accepts', b.allowed.join(', '));
    $('boxPayNote').textContent = b.payWith === 'cash' ? t('ui_paid_cash') : t('ui_paid_from_vault');
    $('boxSizes').innerHTML = b.sizes.map(s => `
      <div class="row">
        <div class="badge">&#128274;</div>
        <div class="row-main"><div class="row-title">${esc(s.label)}</div><div class="row-sub">${esc(t('ui_lockbox_capacity', s.capacity) + (s.rent > 0 ? ' · ' + t('ui_rent_per', fmt(s.rent), b.rentDays) : ''))}</div></div>
        <div class="amt">${fmt(s.price)}</div>
        <button class="wood-btn small-btn rent-btn" data-size="${esc(s.id)}">${esc(t('ui_rent'))}</button>
      </div>`).join('');
    document.querySelectorAll('.rent-btn').forEach(x => x.onclick = () => act('buyLockbox', { size: x.dataset.size }));
    return;
  }
  $('boxLabel').textContent = box.label;
  $('boxUsed').textContent = t('ui_lockbox_used', box.used, box.capacity);
  const pct = box.capacity > 0 ? Math.min(100, box.used / box.capacity * 100) : 100;
  $('boxMeter').style.width = pct + '%';
  $('boxMeter').classList.toggle('full', pct >= 100);
  const upBtn = $('boxUpgradeBtn');
  const isUpSize = box.maxUpgrades > 0 && (box.canUpgrade || box.upgrades > 0);
  upBtn.classList.toggle('hidden', !isUpSize);
  upBtn.textContent = box.canUpgrade ? t('ui_enlarge', box.upgradeStep, fmt(box.upgradePrice)) : t('ui_lockbox_maxed');
  upBtn.dataset.locked = box.canUpgrade ? '' : '1';
  upBtn.onclick = () => { if (box.canUpgrade) act('upgradeLockbox', {}); };

  const rr = box.rent;
  $('boxRentRow').classList.toggle('hidden', !rr);
  if (rr) {
    $('boxRent').textContent = rr.overdue ? t('ui_rent_overdue', fmtDate(rr.due + rr.graceDays * 86400)) : t('ui_rent_paid_until', fmtDate(rr.due));
    $('boxRent').className = 'fee' + (rr.overdue ? ' late' : '');
    const rb = $('boxRentBtn');
    rb.textContent = t('ui_pay_rent', fmt(rr.price));
    rb.dataset.locked = rr.canPay ? '' : '1';
    rb.disabled = !rr.canPay;
    rb.onclick = () => { if (rr.canPay) act('payRent', {}); };
  }

  $('boxStored').innerHTML = box.items.length ? box.items.map(it => `
    <div class="row">${itemImg(b, it)}
      <div class="row-main"><div class="row-title">${esc(it.label)}</div></div>
      <div class="amt">x${it.amount}</div>
      <button class="wood-btn small-btn box-take" data-item="${esc(it.name)}" data-max="${it.amount}">${esc(t('ui_take'))}</button>
    </div>`).join('') : `<div class="empty">${esc(t('ui_lockbox_empty'))}</div>`;
  $('boxCarry').innerHTML = b.carry.length ? b.carry.map(it => `
    <div class="row">${itemImg(b, it)}
      <div class="row-main"><div class="row-title">${esc(it.label)}</div></div>
      <div class="amt">x${it.amount}</div>
      <button class="wood-btn small-btn box-store" data-item="${esc(it.name)}" data-max="${it.amount}">${esc(t('ui_store'))}</button>
    </div>`).join('') : `<div class="empty">${esc(t('ui_nothing_to_store'))}</div>`;

  const qty = max => { const q = parseInt($('boxQty').value, 10); return q > 0 ? q : max; };
  document.querySelectorAll('.box-take').forEach(x => x.onclick = () =>
    act('lockboxWithdraw', { item: x.dataset.item, qty: qty(+x.dataset.max) }));
  document.querySelectorAll('.box-store').forEach(x => x.onclick = () =>
    act('lockboxDeposit', { item: x.dataset.item, qty: Math.min(qty(+x.dataset.max), Math.max(0, box.capacity - box.used)) || qty(+x.dataset.max) }));
}

function render(d) {
  state = d;
  $('bankLabel').textContent = d.label;
  $('customer').textContent = d.name || t('ui_customer');
  $('balance').textContent = fmt(d.balance);
  $('cash').textContent = fmt(d.cash);
  $('openView').classList.toggle('hidden', !!d.hasAccount);
  $('mainView').classList.toggle('hidden', !d.hasAccount);
  $('openFee').textContent = d.openFee > 0 ? t('ui_opening_fee', fmt(d.openFee), fmt(d.cash)) : t('ui_free_to_open');
  const canAfford = (d.cash || 0) >= (d.openFee || 0);
  $('openFee').classList.toggle('afford', canAfford);
  $('openFee').classList.toggle('no-afford', !canAfford);
  $('openBtn').disabled = !canAfford;

  const others = d.branches.filter(b => b.id !== d.bankId && b.open);
  $('wireEmpty').classList.toggle('hidden', others.length > 0);
  $('wireForm').classList.toggle('hidden', others.length === 0);
  const dd = $('wireTarget'), prev = dd.dataset.value;
  setupDd(dd, others.map(b => ({ value: b.id, label: `${b.label} — ${fmt(b.balance)}` })),
    others.some(b => b.id === prev) ? prev : (others[0] && others[0].id));

  $('branchList').innerHTML = d.branches.map(b => `
    <div class="row">
      <div class="badge">&#127974;</div>
      <div class="row-main"><div class="row-title">${esc(b.label)}</div>
        <div class="row-sub ${b.open ? '' : 'closed'}">${!b.open ? t('ui_branch_no_account') : b.id === d.bankId ? t('ui_branch_here') : t('ui_branch_visit')}</div></div>
      ${b.id === d.homeBank ? `<span class="pill">${esc(t('ui_pill_home'))}</span>` : ''}
      ${b.id === d.bankId ? `<span class="pill">${esc(t('ui_pill_here'))}</span>` : ''}
      ${b.id === d.bankId && b.open && b.id !== d.homeBank ? `<button class="wood-btn home-btn" title="${esc(t('ui_home_hint'))}">${esc(t('ui_make_home'))}</button>` : ''}
      <div class="amt ${b.balance > 0 ? 'pos' : ''}">${fmt(b.balance)}</div>
    </div>`).join('');
  document.querySelectorAll('.home-btn').forEach(b => b.onclick = () => act('setHome', {}));

  $('ledgerList').innerHTML = d.history.length ? d.history.map(h => {
    const tx = TX[h.type] || { icon: '&#8226;', label: h.type, sign: 1 };
    const date = h.ts ? new Date(h.ts * 1000).toLocaleDateString() : '';
    return `<div class="row"><div class="badge">${tx.icon}</div>
      <div class="row-main"><div class="row-title">${esc(t(tx.label))}</div><div class="row-sub">${esc(h.note || date)}</div></div>
      <div class="amt ${Number(h.amount) === 0 || tx.sign === 0 ? '' : tx.sign > 0 ? 'pos' : 'neg'}">${Number(h.amount) === 0 ? esc(t('ui_free')) : (tx.sign > 0 ? '+' : tx.sign < 0 ? '-' : '') + fmt(h.amount)}</div></div>`;
  }).join('') : `<div class="empty">${esc(t('ui_no_transactions'))}</div>`;
  calcFee();
  renderLoans(d.loan);
  renderLockbox(d.lockbox);
  renderSend(d.send);
  renderInterest(d.interest);
  renderBusiness(d.business);
  $('statementRow').classList.toggle('hidden', !d.statement);
}

// ---- send money to a citizen ----
let wireMode = 'own';
function setWireMode(m) {
  wireMode = m;
  document.querySelectorAll('#wireModes .chip').forEach(c => c.classList.toggle('active', c.dataset.mode === m));
  $('wireOwn').classList.toggle('hidden', m !== 'own');
  $('wireCitizen').classList.toggle('hidden', m !== 'citizen');
}
function calcSendFee() {
  const s = state && state.send; if (!s) return;
  const a = parseFloat($('sendAmount').value) || 0;
  const fee = a > 0 ? Math.max(s.minFee, Math.round(a * s.feePercent) / 100) : 0;
  $('sendFeeInfo').textContent = t('ui_fee_info', s.feePercent, fmt(fee), fmt(a + fee)) + (s.dailyLeft == null ? '' : ' · ' + t('ui_send_daily_left', fmt(s.dailyLeft)));
}
function renderSend(s) {
  $('wireModes').classList.toggle('hidden', !s);
  if (!s) { setWireMode('own'); return; }
  setWireMode(wireMode);
  calcSendFee();
}

function renderInterest(i) {
  const el = $('interestInfo');
  el.classList.toggle('hidden', !i);
  if (i) el.textContent = t('ui_interest_info', i.percent, fmt(i.cap), fmt(i.min)) + (i.nextAt ? ' · ' + t('ui_interest_next', fmtDate(i.nextAt)) : '');
}

// ---- business (job / gang) accounts ----
function renderBusiness(b) {
  $('bizTabBtn').classList.toggle('hidden', !b);
  if (!b) return;
  $('bizList').innerHTML = b.orgs.length ? b.orgs.map(o => {
    const head = `<div class="biz-head"><div class="badge">&#9874;</div><div class="row-title">${esc(o.label)}</div>` +
      `<span class="pill">${esc(t(o.kind === 'gang' ? 'ui_biz_gang' : 'ui_biz_job'))}</span>` +
      (o.isBoss ? `<span class="pill">${esc(t('ui_biz_boss'))}</span>` : '') + `</div>`;
    if (!o.hasAccount) {
      return `<div class="biz" data-org="${esc(o.key)}">${head}` + (o.canOpen
        ? `<button class="wood-btn biz-open">${esc(t('ui_biz_open', fmt(b.openFee)))}</button>`
        : `<div class="desc">${esc(t('ui_biz_boss_must_open'))}</div>`) + `</div>`;
    }
    let body = `<div class="biz-bal">${fmt(o.balance)}</div>
      <input type="number" class="input biz-amt" placeholder="${esc(t('ui_amount'))}" min="0" step="0.01">
      <div class="actions"><button class="wood-btn biz-dep">${esc(t('ui_deposit'))}</button>${o.canWithdraw ? `<button class="wood-btn biz-wd">${esc(t('ui_withdraw'))}</button>` : ''}</div>`;
    if (!o.canWithdraw) body += `<div class="fee">${esc(t('ui_biz_no_withdraw'))}</div>`;
    else if (!o.isBoss && b.limit > 0) body += `<div class="fee">${esc(t('ui_biz_limit', fmt(b.limit)))}</div>`;
    if (o.isBoss) {
      const ms = o.members || [];
      body += `<div class="list-title">${esc(t('ui_biz_members', ms.length, b.maxMembers))}</div>` +
        (ms.length ? ms.map(m => `<div class="biz-member"><span>${esc(m.name || m.citizenid)} · ${esc(m.citizenid)}</span>` +
          `<button class="wood-btn small-btn biz-rm" data-cid="${esc(m.citizenid)}">${esc(t('ui_biz_remove'))}</button></div>`).join('')
          : `<div class="fee">${esc(t('ui_biz_no_members'))}</div>`) +
        `<div class="biz-add"><input type="text" class="input biz-cid" placeholder="${esc(t('ui_send_citizen_id'))}" maxlength="50" autocomplete="off" spellcheck="false">` +
        `<button class="wood-btn small-btn biz-addbtn">${esc(t('ui_biz_add'))}</button></div>`;
    }
    return `<div class="biz" data-org="${esc(o.key)}">${head}${body}</div>`;
  }).join('') : `<div class="empty">${esc(t('ui_biz_none'))}</div>`;

  const org = x => x.closest('.biz').dataset.org;
  const amt = x => parseFloat(x.closest('.biz').querySelector('.biz-amt').value);
  document.querySelectorAll('.biz-open').forEach(x => x.onclick = () => act('bizOpen', { org: org(x) }));
  document.querySelectorAll('.biz-dep').forEach(x => x.onclick = () => { const a = amt(x); if (a > 0) act('bizDeposit', { org: org(x), amount: a }); });
  document.querySelectorAll('.biz-wd').forEach(x => x.onclick = () => { const a = amt(x); if (a > 0) act('bizWithdraw', { org: org(x), amount: a }); });
  document.querySelectorAll('.biz-addbtn').forEach(x => x.onclick = () => {
    const c = x.closest('.biz').querySelector('.biz-cid').value.trim(); if (c) act('bizAddMember', { org: org(x), citizen: c });
  });
  document.querySelectorAll('.biz-rm').forEach(x => x.onclick = () => act('bizRemoveMember', { org: org(x), citizen: x.dataset.cid }));
}

async function act(name, body) {
  if (busy) return;
  busy = true;
  document.querySelectorAll('.wood-btn').forEach(b => b.disabled = true);
  await post(name, body);
  setTimeout(() => { busy = false; document.querySelectorAll('.wood-btn').forEach(b => b.disabled = false); if (state) { $('openBtn').disabled = (state.cash || 0) < (state.openFee || 0); $('boxUpgradeBtn').disabled = !!$('boxUpgradeBtn').dataset.locked; $('boxRentBtn').disabled = !!$('boxRentBtn').dataset.locked; } }, 500);
}

function close() { closeDds(); $('app').classList.add('hidden'); post('close'); }

window.addEventListener('message', e => {
  const m = e.data;
  if (m.action === 'open') { if (m.locales) { L = m.locales; applyI18n(); } render(m.data); setTab('vault'); $('amount').value = ''; $('wireAmount').value = ''; $('loanAmount').value = ''; $('loanPayAmount').value = ''; $('boxQty').value = ''; $('sendCid').value = ''; $('sendAmount').value = ''; $('sendWho').textContent = ''; setWireMode('own'); $('app').classList.remove('hidden'); window.restorePanelPos && window.restorePanelPos(); }
  else if (m.action === 'update') {
    // money moved -> the action went through, so clear the amount fields
    const moved = state && (state.balance !== m.data.balance || state.cash !== m.data.cash);
    render(m.data);
    if (moved) ['amount', 'wireAmount', 'loanAmount', 'loanPayAmount', 'boxQty', 'sendAmount'].forEach(id => $(id).value = '');
    calcFee(); loanRepayInfo(); calcSendFee();
  }
  else if (m.action === 'close') { closeDds(); $('app').classList.add('hidden'); }
});

document.querySelectorAll('[data-tab]').forEach(t => t.addEventListener('click', () => setTab(t.dataset.tab)));
document.querySelectorAll('.chip[data-q]').forEach(c => c.addEventListener('click', () => {
  const q = c.dataset.q;
  $('amount').value = q === 'all-cash' ? (state?.cash || 0) : q === 'all-bank' ? (state?.balance || 0) : q;
}));
$('depositBtn').onclick = () => { const a = parseFloat($('amount').value); if (a > 0) act('deposit', { amount: a }); };
$('withdrawBtn').onclick = () => { const a = parseFloat($('amount').value); if (a > 0) act('withdraw', { amount: a }); };
$('wireBtn').onclick = () => { const a = parseFloat($('wireAmount').value), t = $('wireTarget').dataset.value; if (a > 0 && t) act('transfer', { target: t, amount: a }); };
$('openBtn').onclick = () => act('openAccount', {});
$('wireAmount').addEventListener('input', calcFee);
$('loanAmount').addEventListener('input', loanRepayInfo);
$('loanMax').onclick = () => { if (state?.loan) { $('loanAmount').value = state.loan.max; loanRepayInfo(); } };
// Enter submits the main action of the focused field
[['amount', 'depositBtn'], ['wireAmount', 'wireBtn'], ['sendAmount', 'sendBtn'], ['loanAmount', 'loanTakeBtn'], ['loanPayAmount', 'loanPayBank']].forEach(([inp, btn]) =>
  $(inp).addEventListener('keydown', e => { if (e.key === 'Enter') $(btn).click(); }));
$('loanTakeBtn').onclick = () => { const a = parseFloat($('loanAmount').value); if (a > 0) act('takeLoan', { amount: a }); };
$('loanPayAll').onclick = () => { if (state?.loan?.active) $('loanPayAmount').value = state.loan.active.owed; };
$('loanPayBank').onclick = () => { const a = parseFloat($('loanPayAmount').value); if (a > 0) act('repayLoan', { amount: a, method: 'bank' }); };
$('loanPayCash').onclick = () => { const a = parseFloat($('loanPayAmount').value); if (a > 0) act('repayLoan', { amount: a, method: 'cash' }); };
document.querySelectorAll('#wireModes .chip').forEach(c => c.onclick = () => setWireMode(c.dataset.mode));
$('sendAmount').addEventListener('input', calcSendFee);
$('sendBtn').onclick = () => {
  const a = parseFloat($('sendAmount').value), c = $('sendCid').value.trim();
  if (a > 0 && c) act('sendMoney', { citizen: c, amount: a });
};
// show the recipient's name while typing a citizen id
let lookupTimer = null, lookupSeq = 0;
$('sendCid').addEventListener('input', () => {
  clearTimeout(lookupTimer);
  const v = $('sendCid').value.trim(), who = $('sendWho');
  who.textContent = ''; who.className = 'fee';
  if (v.length < 3) return;
  const seq = ++lookupSeq;
  lookupTimer = setTimeout(async () => {
    const r = await postJson('lookupRecipient', { citizen: v });
    if (seq !== lookupSeq) return;
    if (r && r.name) { who.textContent = t('ui_send_lookup_found', r.name); who.className = 'fee ok'; }
    else { who.textContent = t('ui_send_lookup_none'); who.className = 'fee bad'; }
  }, 450);
});
$('statementBtn').onclick = () => act('sendStatement', {});
$('closeBtn').onclick = close;
document.addEventListener('keydown', e => { if (e.key === 'Escape' && !$('app').classList.contains('hidden')) close(); });

// ---- draggable panel (drag by header, position remembered) ----
(() => {
  const panel = document.querySelector('.panel'), header = document.querySelector('.header');
  const KEY = 'rsg-banking-pos';
  let drag = null;

  const clamp = (x, y) => [
    Math.min(Math.max(0, x), window.innerWidth - panel.offsetWidth),
    Math.min(Math.max(0, y), window.innerHeight - panel.offsetHeight),
  ];
  const place = (x, y) => {
    [x, y] = clamp(x, y);
    panel.classList.add('dragged');
    panel.style.left = x + 'px'; panel.style.top = y + 'px';
  };

  window.restorePanelPos = () => {
    try {
      const p = JSON.parse(localStorage.getItem(KEY));
      if (p) requestAnimationFrame(() => place(p.x, p.y));
    } catch (e) {}
  };

  header.addEventListener('mousedown', e => {
    if (e.button !== 0 || e.target.closest('.circle-btn')) return;
    const r = panel.getBoundingClientRect();
    drag = { dx: e.clientX - r.left, dy: e.clientY - r.top };
    place(r.left, r.top);
    panel.classList.add('dragging');
    e.preventDefault();
  });
  document.addEventListener('mousemove', e => { if (drag) place(e.clientX - drag.dx, e.clientY - drag.dy); });
  document.addEventListener('mouseup', () => {
    if (!drag) return;
    drag = null; panel.classList.remove('dragging');
    try { localStorage.setItem(KEY, JSON.stringify({ x: panel.offsetLeft, y: panel.offsetTop })); } catch (e) {}
  });
  // double-click header to re-centre
  header.addEventListener('dblclick', e => {
    if (e.target.closest('.circle-btn')) return;
    panel.classList.remove('dragged'); panel.style.left = panel.style.top = '';
    try { localStorage.removeItem(KEY); } catch (e) {}
  });
})();
