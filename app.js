(function () {
  "use strict";

  const CONFIG = window.VIALSEG_INVENTORY_CONFIG || {};
  const STORAGE_KEY = "vialseg-inventory-demo-v1";
  const VIEW_NAMES = { overview: "Resumen", items: "Materiales", movements: "Movimientos", reports: "Reportes", costs: "Costos", replenishment: "Reposición" };
  const ICONS = {
    grid: "M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z",
    box: "m12 3 9 5-9 5-9-5 9-5zM3 8v9l9 5 9-5V8M12 13v9",
    arrows: "M7 7h13l-3-3m3 3-3 3M17 17H4l3 3m-3-3 3-3",
    bell: "M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4",
    settings: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm7.4-3a7.4 7.4 0 0 0-.1-1.2l2-1.6-2-3.4-2.4 1a7.5 7.5 0 0 0-2-1.2L14.5 3h-4l-.4 2.6a7.5 7.5 0 0 0-2 1.2l-2.4-1-2 3.4 2 1.6a7.4 7.4 0 0 0 0 2.4l-2 1.6 2 3.4 2.4-1a7.5 7.5 0 0 0 2 1.2l.4 2.6h4l.4-2.6a7.5 7.5 0 0 0 2-1.2l2.4 1 2-3.4-2-1.6c.1-.4.1-.8.1-1.2z",
    logout: "M10 17l5-5-5-5m5 5H3m9-9h7a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-7",
    menu: "M4 6h16M4 12h16M4 18h16",
    search: "m21 21-4.4-4.4M19 10.5a8.5 8.5 0 1 1-17 0 8.5 8.5 0 0 1 17 0z",
    alert: "M12 9v4m0 4h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z",
    chart: "M3 3v18h18M7 15l4-4 3 3 5-6",
    coin: "M12 2v20m5-15H9.5a3.5 3.5 0 0 0 0 7H14a3.5 3.5 0 0 1 0 7H6",
    clock: "M12 8v4l3 2m6-2a9 9 0 1 1-18 0 9 9 0 0 1 18 0z",
    plus: "M12 5v14m-7-7h14",
    edit: "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4z",
    download: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4m4-5 5 5 5-5m-5 5V3",
    upload: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4m12-7-5-5-5 5m5-5v12",
    arrow: "M5 12h14m-7-7 7 7-7 7",
    check: "m5 12 4 4L19 6",
    close: "m18 6-12 12M6 6l12 12"
  };

  const state = { mode: null, session: null, user: null, rememberSession: false, items: [], movements: [], view: "overview", itemSearch: "", itemCodeSearch: "", itemLocation: "all", itemCategory: "all", itemClass: "all", itemStatus: "all", movementType: "all", movementSearch: "", reportFrom: "", reportTo: "", priceHistoryItem: "", priceHistoryData: [] };
  const $ = (selector, root) => (root || document).querySelector(selector);
  const $$ = (selector, root) => Array.from((root || document).querySelectorAll(selector));
  const esc = (value) => String(value == null ? "" : value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c]));
  const num = (v) => Number.isFinite(Number(v)) ? Number(v) : 0;
  const money = (v) => new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 }).format(num(v));
  const moneyUSD = (v) => new Intl.NumberFormat("es-AR", { style: "currency", currency: "USD", maximumFractionDigits: 2 }).format(num(v));
  const quantity = (v) => new Intl.NumberFormat("es-AR", { maximumFractionDigits: 2 }).format(num(v));
  const shortDate = (v) => {
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) return "—";
    return new Intl.DateTimeFormat("es-AR", { day: "2-digit", month: "short", year: "numeric" }).format(d);
  };
  const relativeDate = (days) => new Date(Date.now() - days * 86400000).toISOString();
  const initials = (name) => String(name || "AD").split(/[\s@.]+/).filter(Boolean).slice(0, 2).map((x) => x[0]).join("").toUpperCase() || "AD";
  const authEmailForUsername = (username) => username.trim().toLowerCase() + "@vialseg-inventario.example.com";
  const icon = (name, cls) => '<svg class="' + (cls || "") + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + (ICONS[name] || ICONS.box) + '"/></svg>';
  const show = (el) => { if (el) el.hidden = false; };
  const hide = (el) => { if (el) el.hidden = true; };
  const configured = () => Boolean(CONFIG.supabaseUrl && CONFIG.supabaseKey);
  async function fetchBlueQuote() {
    const response = await fetch("https://dolarapi.com/v1/dolares/blue", { cache: "no-store" });
    if (!response.ok) throw new Error("La cotización del dólar blue no está disponible. Intentá de nuevo.");
    const quote = await response.json();
    const rate = num(quote.venta);
    if (!(rate > 0)) throw new Error("No se recibió una cotización vendedora válida.");
    return { rate: rate, at: quote.fechaActualizacion || new Date().toISOString(), source: "DolarAPI · dólar blue venta" };
  }

  function seedItems() {
    return [
      { id: "demo-1", sku: "EL-1042", name: "Módulo de control", category: "Electrónica", unit: "u", stock: 8, unitCost: 82500, monthlyUse: 11, safetyStock: 10, leadDays: 18, minimumLot: 5, supplier: "Electro Sistemas", location: "Estante A · Nivel 2", replenish: true, active: true, updatedAt: relativeDate(0) },
      { id: "demo-2", sku: "CA-0218", name: "Cable de alimentación", category: "Cableado", unit: "m", stock: 84, unitCost: 1850, monthlyUse: 55, safetyStock: 30, leadDays: 7, minimumLot: 25, supplier: "Cables del Norte", location: "Estante C · Nivel 1", replenish: true, active: true, updatedAt: relativeDate(1) },
      { id: "demo-3", sku: "SE-0305", name: "Sensor de velocidad", category: "Electrónica", unit: "u", stock: 3, unitCost: 46800, monthlyUse: 7, safetyStock: 5, leadDays: 22, minimumLot: 5, supplier: "Electro Sistemas", location: "Estante A · Nivel 1", replenish: true, active: true, updatedAt: relativeDate(2) },
      { id: "demo-4", sku: "FI-0081", name: "Fusible industrial", category: "Eléctrico", unit: "u", stock: 126, unitCost: 760, monthlyUse: 28, safetyStock: 20, leadDays: 4, minimumLot: 50, supplier: "Suministros Delta", location: "Estante B · Cajón 4", replenish: true, active: true, updatedAt: relativeDate(3) },
      { id: "demo-5", sku: "PL-0017", name: "Placa electrónica", category: "Electrónica", unit: "u", stock: 2, unitCost: 124000, monthlyUse: 3, safetyStock: 4, leadDays: 30, minimumLot: 2, supplier: "TecnoPartes", location: "Armario seguro · B", replenish: true, active: true, updatedAt: relativeDate(5) },
      { id: "demo-6", sku: "MO-0110", name: "Soporte de montaje", category: "Mecánica", unit: "u", stock: 19, unitCost: 9200, monthlyUse: 10, safetyStock: 8, leadDays: 12, minimumLot: 10, supplier: "Metalúrgica Roca", location: "Estante D · Nivel 3", replenish: true, active: true, updatedAt: relativeDate(5) },
      { id: "demo-7", sku: "CA-0400", name: "Conector estanco", category: "Cableado", unit: "u", stock: 7, unitCost: 3200, monthlyUse: 5, safetyStock: 8, leadDays: 9, minimumLot: 10, supplier: "Cables del Norte", location: "Estante C · Cajón 2", replenish: false, active: true, updatedAt: relativeDate(7) },
      { id: "demo-8", sku: "HE-0009", name: "Kit de fijaciones", category: "Mecánica", unit: "kit", stock: 52, unitCost: 1450, monthlyUse: 14, safetyStock: 20, leadDays: 6, minimumLot: 20, supplier: "Suministros Delta", location: "Estante D · Cajón 1", replenish: true, active: true, updatedAt: relativeDate(9) }
    ];
  }

  function seedMovements(items) {
    const find = (sku) => items.find((item) => item.sku === sku);
    const specs = [
      ["EL-1042", "consumo", -2, 10, 8, "Uso en mantenimiento preventivo", "OT-2037", 0],
      ["CA-0218", "ingreso", 50, 34, 84, "Recepción de compra", "OC-1182", 1],
      ["SE-0305", "consumo", -1, 4, 3, "Reemplazo de equipo en campo", "OT-2031", 2],
      ["FI-0081", "ingreso", 100, 26, 126, "Reposición de stock", "OC-1175", 3],
      ["PL-0017", "ajuste", -1, 3, 2, "Conteo físico de cierre", "CONTEO-09", 5]
    ];
    return specs.map((s, i) => ({ id: "demo-m-" + i, itemId: find(s[0]).id, sku: s[0], itemName: find(s[0]).name, type: s[1], quantity: s[2], stockBefore: s[3], stockAfter: s[4], note: s[5], reference: s[6], actor: "Administración", createdAt: relativeDate(s[7]) }));
  }

  function loadDemoData() {
    try {
      const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
      if (saved && Array.isArray(saved.items) && Array.isArray(saved.movements)) {
        state.items = saved.items.map((item) => ({ ...item, minimumLot: Math.max(0, num(item.minimumLot !== undefined ? item.minimumLot : item.lotSize)) }));
        state.movements = saved.movements;
        return;
      }
    } catch (_) {}
    state.items = seedItems();
    state.movements = seedMovements(state.items);
    persistDemo();
  }
  function persistDemo() {
    if (state.mode !== "demo") return;
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ items: state.items, movements: state.movements })); }
    catch (_) { toast("No se pudo guardar en este navegador.", "error"); }
  }

  function itemFromRow(row) {
    return {
      id: row.id, sku: row.sku, name: row.nombre, category: row.categoria || "General", unit: row.unidad || "u",
      stock: num(row.stock), unitCost: num(row.costo_unitario), avgCostUsd: num(row.costo_promedio_usd), monthlyUse: num(row.consumo_mensual),
      safetyStock: num(row.stock_seguridad), leadDays: num(row.plazo_dias), minimumLot: Math.max(0, num(row.lote_reposicion)),
      supplier: row.proveedor || "", location: row.ubicacion || "", replenish: row.se_repone !== false, active: row.activo !== false,
      updatedAt: row.updated_at || row.created_at, quoteRate: num(row.cotizacion_blue_base)
    };
  }
  function actorLabel(actor) {
    const value = String(actor || "").trim();
    const fakeDomain = "@vialseg-inventario.example.com";
    return value.toLowerCase().endsWith(fakeDomain) ? value.slice(0, -fakeDomain.length) : value;
  }
  function currentActor() {
    const user = state.user || {};
    const username = user.user_metadata && user.user_metadata.username;
    if (username) return username;
    const email = String(user.email || "").trim();
    const fakeDomain = "@vialseg-inventario.example.com";
    if (email.toLowerCase().endsWith(fakeDomain)) return email.slice(0, -fakeDomain.length);
    return user.name || email || "Administración";
  }

  function movementFromRow(row) {
    return { id: row.id, itemId: row.item_id, sku: row.sku, itemName: row.item_name, type: row.tipo, quantity: num(row.cantidad), stockBefore: num(row.stock_antes), stockAfter: num(row.stock_despues), note: row.nota || "", reference: row.referencia || "", actor: row.actor || "", createdAt: row.created_at, unitCostArs: num(row.precio_unitario_ars), unitCostUsd: num(row.precio_unitario_usd), blueRate: num(row.cotizacion_blue), quoteAt: row.cotizacion_fecha, quoteSource: row.cotizacion_fuente || "" };
  }
  function itemToRow(item) {
    return { sku: item.sku, nombre: item.name, categoria: item.category, unidad: item.unit, stock: num(item.stock), costo_unitario: num(item.unitCost), costo_promedio_usd: num(item.avgCostUsd), cotizacion_blue_base: num(item.quoteRate), consumo_mensual: num(item.monthlyUse), stock_seguridad: num(item.safetyStock), plazo_dias: num(item.leadDays), lote_reposicion: Math.max(0, num(item.minimumLot)), proveedor: item.supplier || "", ubicacion: item.location || "", se_repone: item.replenish !== false, activo: item.active !== false, updated_at: new Date().toISOString() };
  }

  function getSession() {
    const key = "vialseg-inventory-session";
    try {
      sessionStorage.removeItem(key);
      const saved = localStorage.getItem(key);
      state.rememberSession = Boolean(saved);
      return saved ? JSON.parse(saved) : null;
    } catch (_) { state.rememberSession = false; return null; }
  }
  function putSession(s, remember) {
    const key = "vialseg-inventory-session";
    state.session = s;
    try { sessionStorage.removeItem(key); } catch (_) {}
    if (!s) {
      state.rememberSession = false;
      try { localStorage.removeItem(key); } catch (_) {}
      return;
    }
    if (typeof remember === "boolean") state.rememberSession = remember;
    if (!state.rememberSession) {
      try { localStorage.removeItem(key); } catch (_) {}
      return;
    }
    try { localStorage.setItem(key, JSON.stringify(s)); }
    catch (_) { state.rememberSession = false; try { localStorage.removeItem(key); } catch (_) {} }
  }
  async function authRequest(path, body) {
    const response = await fetch(CONFIG.supabaseUrl.replace(/\/$/, "") + "/auth/v1/" + path, {
      method: "POST", headers: { "Content-Type": "application/json", apikey: CONFIG.supabaseKey },
      body: JSON.stringify(body)
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) { const message = data.msg || data.message || data.error_description || ""; if (/invalid login credentials/i.test(message)) throw new Error("El usuario o la contraseña son incorrectos."); throw new Error(message || "No se pudo iniciar sesión."); }
    return data;
  }
  async function refreshAuth() {
    const session = state.session || getSession();
    if (!session || !session.refresh_token) return false;
    try {
      const data = await authRequest("token?grant_type=refresh_token", { refresh_token: session.refresh_token });
      putSession({ access_token: data.access_token, refresh_token: data.refresh_token, expires_at: Date.now() + (data.expires_in || 3600) * 1000, user: data.user }, state.rememberSession);
      state.user = data.user;
      return true;
    } catch (_) { putSession(null); return false; }
  }
  async function api(path, options, retry) {
    const session = state.session || getSession();
    if (!session || !session.access_token) throw new Error("La sesión expiró. Volvé a ingresar.");
    if (session.expires_at && session.expires_at < Date.now() + 30000 && await refreshAuth()) return api(path, options, true);
    const headers = Object.assign({ apikey: CONFIG.supabaseKey, Authorization: "Bearer " + (state.session || session).access_token, "Content-Type": "application/json" }, (options && options.headers) || {});
    const response = await fetch(CONFIG.supabaseUrl.replace(/\/$/, "") + "/rest/v1/" + path, Object.assign({}, options || {}, { headers: headers }));
    if (response.status === 401 && !retry && await refreshAuth()) return api(path, options, true);
    const text = await response.text();
    if (!response.ok) {
      let message = text;
      try { const data = JSON.parse(text); message = data.message || data.details || data.hint || data.error_description || text; } catch (_) {}
      throw new Error(message || "Error de conexión con el inventario.");
    }
    if (!text) return null;
    try { return JSON.parse(text); } catch (_) { return text; }
  }
  async function loadRemoteData() {
    const userId = state.session && state.session.user && state.session.user.id;
    if (!userId) throw new Error("La sesión no tiene un usuario válido.");
    const membership = await api("inventory_members?select=rol,activo&user_id=eq." + encodeURIComponent(userId) + "&activo=eq.true");
    if (!membership || !membership.length) throw new Error("Tu cuenta todavía no tiene acceso al inventario. Pedile al administrador que la habilite.");
    const rows = await Promise.all([
      api("inventory_items?select=*&activo=eq.true&order=nombre.asc"),
      api("inventory_movements?select=*&order=created_at.desc&limit=500")
    ]);
    state.items = (rows[0] || []).map(itemFromRow);
    state.movements = (rows[1] || []).map(movementFromRow);
    await initializeUsdCostBaseline();
  }

  async function initializeUsdCostBaseline() {
    const missing = state.items.filter((item) => !(item.avgCostUsd > 0) && item.unitCost > 0);
    if (!missing.length) return;
    try {
      const quote = await fetchBlueQuote();
      for (const item of missing) {
        item.avgCostUsd = item.unitCost / quote.rate;
        item.quoteRate = quote.rate;
        if (state.mode !== "demo") await api("inventory_items?id=eq." + encodeURIComponent(item.id), { method: "PATCH", body: JSON.stringify({ costo_promedio_usd: item.avgCostUsd, cotizacion_blue_base: quote.rate }) });
      }
    } catch (_) { /* Un fallo de cotización no bloquea el acceso al inventario. */ }
  }

  function reorderPoint(item) {
    return num(item.safetyStock) + (num(item.monthlyUse) / 30) * num(item.leadDays);
  }
  function minimumOrderQuantity(item) {
    if (!item.replenish || (num(item.safetyStock) <= 0 && num(item.monthlyUse) <= 0) || num(item.stock) > reorderPoint(item)) return 0;
    const faltanteHastaPuntoDePedido = Math.max(0, reorderPoint(item) - num(item.stock));
    return Math.max(faltanteHastaPuntoDePedido, Math.max(0, num(item.minimumLot)));
  }
  function stockStatus(item) {
    if (!item.replenish) return "non";
    if (num(item.safetyStock) <= 0 && num(item.monthlyUse) <= 0) return "unknown";
    if (num(item.stock) <= num(item.safetyStock) && num(item.safetyStock) > 0) return "critical";
    if (num(item.stock) <= reorderPoint(item)) return "low";
    return "ok";
  }
  function withAbc(items) {
    const sorted = items.slice().sort((a, b) => (num(b.monthlyUse) * num(b.avgCostUsd)) - (num(a.monthlyUse) * num(a.avgCostUsd)));
    const total = sorted.reduce((s, item) => s + num(item.monthlyUse) * num(item.avgCostUsd), 0);
    let cumulative = 0;
    const map = {};
    sorted.forEach((item) => {
      const value = num(item.monthlyUse) * num(item.avgCostUsd);
      cumulative += total > 0 ? value / total : 0;
      map[item.id] = total <= 0 ? "C" : cumulative - value / total < 0.8 ? "A" : cumulative - value / total < 0.95 ? "B" : "C";
    });
    return map;
  }
  function activeItems() { return state.items.filter((item) => item.active !== false); }
  function candidates() { return activeItems().filter((item) => minimumOrderQuantity(item) > 0); }
  function criticalItems() { return activeItems().filter((item) => item.replenish && num(item.safetyStock) > 0 && num(item.stock) <= num(item.safetyStock)); }
  function classCounts() {
    const map = withAbc(activeItems());
    return ["A", "B", "C"].map((key) => ({ key: key, count: Object.values(map).filter((v) => v === key).length }));
  }

  function setView(view) {
    if (!VIEW_NAMES[view]) return;
    state.view = view;
    history.replaceState(null, "", "#" + view);
    const sidebar = $("#sidebar");
    if (sidebar) sidebar.classList.remove("open");
    render();
    if (view === "costs") loadPriceHistory(state.priceHistoryItem || (activeItems()[0] && activeItems()[0].id)).catch((error) => toast(error.message || "No se pudo cargar el historial de precios.", "error"));
  }
  function paintIdentity() {
    const who = state.user && (state.user.user_metadata && state.user.user_metadata.username || (state.user.email && state.user.email.split("@")[0]) || state.user.name) || "Administración";
    const name = state.mode === "demo" ? "Administración demo" : who;
    const role = state.mode === "demo" ? "Datos de demostración" : "Inventario Vialseg";
    $("#user-name").textContent = name;
    $("#top-user-name").textContent = name;
    $("#user-role").textContent = role;
    $("#user-avatar").textContent = initials(name);
    $("#top-avatar").textContent = initials(name);
    const chip = $("#mode-chip");
    chip.classList.toggle("demo", state.mode === "demo");
    chip.querySelector("span:last-child").textContent = state.mode === "demo" ? "Demostración" : "Base compartida";
    const navCount = $("#nav-items-count");
    if (navCount) navCount.textContent = activeItems().length;
    const notify = $("#nav-replenishment-count");
    if (notify) {
      notify.textContent = candidates().length;
      notify.hidden = candidates().length === 0;
    }
    $("#notification-dot").hidden = candidates().length === 0;
  }
  function headingActions(view) {
    if (view === "overview") return "";
    if (view === "items") return '<button class="button button-outline" data-action="import-csv">' + icon("upload") + ' Importar CSV</button><button class="button button-outline" data-action="export-items">' + icon("download") + ' Exportar CSV</button><button class="button button-lime" data-action="new-item">' + icon("plus") + ' Nuevo material</button>';
    if (view === "movements") return '<button class="button button-lime" data-action="new-movement">' + icon("plus") + ' Registrar movimiento</button>';
    if (view === "reports") return '<button class="button button-outline" data-action="export-period-report">' + icon("download") + ' Exportar reporte</button>';
    if (view === "replenishment") return '<button class="button button-outline" data-action="export-replenishment">' + icon("download") + ' Exportar lista</button>';
    return "";
  }
  function render() {
    paintIdentity();
    $$(".nav-item").forEach((el) => el.classList.toggle("active", el.dataset.view === state.view));
    $("#breadcrumb-current").textContent = VIEW_NAMES[state.view];
    $("#page-heading").innerHTML = '<div><h1 class="page-title">' + VIEW_NAMES[state.view] + '</h1><p class="page-subtitle">' + viewSubtitle(state.view) + '</p></div><div class="heading-actions">' + headingActions(state.view) + '</div>';
    $("#notice-strip").innerHTML = state.mode === "demo" ? '<div class="demo-banner"><span class="banner-icon">i</span><span><strong>Modo demostración.</strong> Estos datos son ficticios y se guardan únicamente en este navegador.</span><button data-action="open-settings">Ver cómo conectar la base</button></div>' : "";
    const mainContent = $("#main-content");
    mainContent.innerHTML = state.view === "overview" ? renderOverview() : state.view === "items" ? renderItems() : state.view === "movements" ? renderMovements() : state.view === "reports" ? renderReports() : state.view === "costs" ? renderCostAnalysis() : renderReplenishment();
    mainContent.classList.remove("content-enter");
    void mainContent.offsetWidth;
    mainContent.classList.add("content-enter");
    window.setTimeout(() => mainContent.classList.remove("content-enter"), 360);
    $("#footer-date").textContent = new Intl.DateTimeFormat("es-AR", { weekday: "long", day: "numeric", month: "long" }).format(new Date());
    paintIdentity();
  }
  function viewSubtitle(view) {
    return {
      items: "Consultá los materiales y sus parámetros de abastecimiento.",
      reports: "Consultá ingresos, consumos y ajustes en un período.",
      costs: "Compará la evolución del precio de compra en pesos y dólares.",
      replenishment: "Revisá qué materiales conviene reponer."
    }[view] || "";
  }

  function kpi(label, value, foot, iconName, tone) {
    return '<article class="kpi-card"><div class="kpi-top"><span class="kpi-label">' + label + '</span><span class="kpi-icon ' + (tone || "") + '">' + icon(iconName) + '</span></div><div class="kpi-value">' + value + '</div><div class="kpi-foot">' + foot + '</div></article>';
  }
  function lastPurchaseCostUsd(item) {
    const itemId = String(item.id);
    const lastPricedIncome = state.movements
      .filter((movement) => String(movement.itemId || movement.item_id) === itemId && (movement.type || movement.tipo) === "ingreso" && num(movement.unitCostUsd || movement.precio_unitario_usd) > 0)
      .sort((a, b) => new Date(b.createdAt || b.created_at || 0) - new Date(a.createdAt || a.created_at || 0))[0];
    if (lastPricedIncome) return num(lastPricedIncome.unitCostUsd || lastPricedIncome.precio_unitario_usd);
    const ars = num(item.unitCost), rate = num(item.quoteRate);
    return ars > 0 && rate > 0 ? ars / rate : 0;
  }
  function renderOverview() {
    const items = activeItems();
    const value = items.reduce((sum, item) => sum + num(item.stock) * lastPurchaseCostUsd(item), 0);
    const noRestock = items.filter((item) => !item.replenish && num(item.stock) <= num(item.safetyStock));
    const abc = withAbc(items);
    const attention = items.filter((item) => (item.replenish && num(item.stock) <= reorderPoint(item)) || (!item.replenish && num(item.stock) <= num(item.safetyStock))).sort((a, b) => {
      const classOrder = { A: 0, B: 1, C: 2 };
      const byClass = classOrder[abc[a.id] || "C"] - classOrder[abc[b.id] || "C"];
      if (byClass) return byClass;
      return (a.replenish ? num(a.stock) - reorderPoint(a) : -999) - (b.replenish ? num(b.stock) - reorderPoint(b) : -999);
    });
    return '<div class="kpi-grid">' +
      kpi("VALOR DEL STOCK", moneyUSD(value), "Valuado al último precio pagado", "coin", "lime") +
      kpi("BAJO STOCK DE SEGURIDAD", criticalItems().length + noRestock.length, '<span class="down">Revisar disponibilidad</span>', "alert", "alert") +
      kpi("SUGERENCIAS DE REPOSICIÓN", candidates().length, "Según consumo y plazo de entrega", "bell", "") +
      '</div>' +
      '<section class="panel table-panel"><div class="panel-head"><div><h2 class="panel-title">Materiales para revisar <span class="pill-count">' + attention.length + '</span></h2><p class="panel-caption">Resumen de stock y estado de abastecimiento.</p></div><button class="text-link" data-view="items">Ver todos</button></div>' +
      renderItemTable(attention, false) + '</section>' +
      '<section class="panel table-panel" style="margin-top:15px"><div class="panel-head"><div><h2 class="panel-title">Movimientos recientes</h2><p class="panel-caption">Últimos cambios registrados en el inventario.</p></div><button class="text-link" data-view="movements">Ver historial</button></div>' +
      renderMovementTable(state.movements.slice(0, 5), false) + '</section>';
  }

  function statusHtml(item) {
    const status = stockStatus(item);
    if (status === "non") return '<span class="badge neutral">Sin reposición</span>';
    if (status === "unknown") return '<span class="badge neutral">Configurar</span>';
    if (status === "critical") return '<span class="badge critical">Crítico</span>';
    if (status === "low") return '<span class="badge low">Bajo</span>';
    return '<span class="badge ok">En nivel</span>';
  }
  function itemClass(item, abc) { return '<span class="class-badge abc-' + (abc[item.id] || "C").toLowerCase() + '">' + (abc[item.id] || "C") + '</span>'; }
  function thumbClass(item) {
    const cat = String(item.category || "").toLowerCase();
    return cat.includes("cable") ? "cable" : cat.includes("mec") || cat.includes("herra") ? "hardware" : "electronics";
  }
  function renderItemTable(items, actions) {
    const abc = withAbc(activeItems());
    return '<div class="table-scroll"><table class="data-table"><thead><tr><th>MATERIAL</th><th>UBICACIÓN FÍSICA</th><th>ABC</th><th>STOCK ACTUAL</th><th>PUNTO DE PEDIDO</th><th>ESTADO</th>' + (actions ? '<th></th>' : '') + '</tr></thead><tbody>' +
      (items.length ? items.map((item) => {
        const max = Math.max(1, reorderPoint(item) * 1.7, num(item.stock) * 1.15);
        const pct = Math.min(100, Math.round(num(item.stock) / max * 100));
        const level = stockStatus(item);
        return '<tr><td><div class="table-item"><span class="item-thumb ' + thumbClass(item) + '">' + icon("box") + '</span><span><span class="item-name">' + esc(item.name) + '</span><span class="item-sku">' + esc(item.sku) + ' · ' + esc(item.category) + '</span></span></div></td><td>' + (item.location ? esc(item.location) : '<span class="muted">—</span>') + '</td><td>' + itemClass(item, abc) + '</td><td class="stock-cell"><div class="stock-line"><span class="stock-number">' + quantity(item.stock) + ' ' + esc(item.unit) + '</span><span class="stock-bar"><i class="' + (level === "critical" ? "critical" : level === "low" ? "low" : "") + '" style="width:' + pct + '%"></i></span></div></td><td>' + (item.replenish ? quantity(reorderPoint(item)) + ' ' + esc(item.unit) : '<span class="muted">No aplica</span>') + '</td><td>' + statusHtml(item) + '</td>' + (actions ? '<td><div class="actions-cell"><button class="table-action" data-action="new-movement" data-id="' + esc(item.id) + '">Movimiento</button><button class="table-action icon-only" aria-label="Editar ' + esc(item.name) + '" data-action="edit-item" data-id="' + esc(item.id) + '"><span aria-hidden="true">✏️</span></button><button class="table-action icon-only" aria-label="Eliminar ' + esc(item.name) + '" data-action="delete-item" data-id="' + esc(item.id) + '"><span aria-hidden="true">🗑️</span></button></div></td>' : '') + '</tr>';
      }).join("") : '<tr><td colspan="' + (actions ? 7 : 6) + '"><div class="empty-state"><strong>No hay materiales para mostrar</strong>Probá cambiar los filtros o agregá un material al catálogo.</div></td></tr>') +
      '</tbody></table></div>';
  }
  function filteredItems() {
    let list = activeItems();
    const q = state.itemSearch.toLowerCase().trim();
    if (q) list = list.filter((i) => String(i.name || "").toLowerCase().includes(q));
    if (state.itemLocation !== "all") { const selectedLocation = String(state.itemLocation || "").trim().replace(/\s+/g, " ").toLocaleLowerCase("es"); list = list.filter((i) => String(i.location || "").trim().replace(/\s+/g, " ").toLocaleLowerCase("es") === selectedLocation); }
    const codeQuery = state.itemCodeSearch.toLowerCase().trim();
    if (codeQuery) list = list.filter((i) => String(i.sku || "").toLowerCase().includes(codeQuery));
    if (state.itemCategory !== "all") list = list.filter((i) => String(i.category || "General").toLowerCase() === state.itemCategory.toLowerCase());
    if (state.itemClass !== "all") {
      const abc = withAbc(activeItems());
      list = list.filter((i) => abc[i.id] === state.itemClass);
    }
    if (state.itemStatus === "critical") list = list.filter((i) => stockStatus(i) === "critical");
    if (state.itemStatus === "low") list = list.filter((i) => stockStatus(i) === "low");
    if (state.itemStatus === "non") list = list.filter((i) => stockStatus(i) === "non");
    if (state.itemStatus === "ok") list = list.filter((i) => stockStatus(i) === "ok");
    return list.sort((a, b) => String(a.sku || "").localeCompare(String(b.sku || ""), "es", { numeric: true, sensitivity: "base" }));
  }
  function renderItems() {
    const list = filteredItems();
    return '<section class="panel table-panel"><div class="panel-head"><div><h2 class="panel-title">Catálogo de materiales <span class="pill-count" id="item-result-count">' + list.length + '</span></h2><p class="panel-caption">El stock se modifica desde Movimientos para conservar el historial.</p></div></div>' +
      '<div class="table-toolbar"><div class="search-wrap"><span class="search-icon">' + icon("search") + '</span><input id="item-search" class="search-input" value="' + esc(state.itemSearch) + '" placeholder="Buscar por nombre"></div><div class="search-wrap"><span class="search-icon">#</span><input id="item-code-search" class="search-input" value="' + esc(state.itemCodeSearch) + '" placeholder="Buscar por código"></div>' +
      '<select id="item-location-filter" class="filter-select" aria-label="Filtrar por ubicación"><option value="all">Todas las ubicaciones</option>' + Array.from(new Set(activeItems().map((item) => String(item.location || "").trim()).filter(Boolean))).sort((a, b) => a.localeCompare(b, "es")).map((location) => '<option value="' + esc(location) + '"' + (state.itemLocation.toLowerCase() === location.toLowerCase() ? " selected" : "") + '>' + esc(location) + '</option>').join("") + '</select>' +
      '<select id="item-category-filter" class="filter-select" aria-label="Filtrar por categoría"><option value="all">Todas las categorías</option>' + Array.from(new Set(activeItems().map((item) => String(item.category || "General").trim()).filter(Boolean))).sort((a, b) => a.localeCompare(b, "es")).map((category) => '<option value="' + esc(category) + '"' + (state.itemCategory.toLowerCase() === category.toLowerCase() ? " selected" : "") + '>' + esc(category) + '</option>').join("") + '</select>' +
      '<select id="item-class-filter" class="filter-select" aria-label="Filtrar por clase ABC"><option value="all">Todas las clases</option><option value="A"' + (state.itemClass === "A" ? " selected" : "") + '>Clase A</option><option value="B"' + (state.itemClass === "B" ? " selected" : "") + '>Clase B</option><option value="C"' + (state.itemClass === "C" ? " selected" : "") + '>Clase C</option></select>' +
      '<select id="item-status-filter" class="filter-select" aria-label="Filtrar por estado"><option value="all">Todos los estados</option><option value="critical"' + (state.itemStatus === "critical" ? " selected" : "") + '>Crítico</option><option value="low"' + (state.itemStatus === "low" ? " selected" : "") + '>Bajo</option><option value="ok"' + (state.itemStatus === "ok" ? " selected" : "") + '>En nivel</option><option value="non"' + (state.itemStatus === "non" ? " selected" : "") + '>Sin reposición</option></select></div>' +
      '<div id="item-table-region">' + renderItemTable(list, true) + '</div></section>';
  }
  function renderMovementTable(movements, actions) {
    return '<div class="table-scroll"><table class="data-table"><thead><tr><th>FECHA</th><th>MATERIAL</th><th>TIPO</th><th>CANTIDAD</th><th>REFERENCIA</th><th>RESPONSABLE</th>' + (actions ? '<th></th>' : '') + '</tr></thead><tbody>' +
      (movements.length ? movements.map((m) => {
        const type = m.type || m.tipo;
        const qty = num(m.quantity !== undefined ? m.quantity : m.cantidad);
        const itemName = m.itemName || m.item_name || "Material eliminado";
        const sku = m.sku || "";
        const date = m.createdAt || m.created_at;
        const note = m.note || m.nota || "";
        const ref = m.reference || m.referencia || "";
        const actor = actorLabel(m.actor || "");
        const iconText = type === "ingreso" ? "↑" : type === "consumo" ? "↓" : "↔";
        const label = type === "ingreso" ? "Ingreso" : type === "consumo" ? "Consumo" : "Ajuste";
        return '<tr><td>' + shortDate(date) + '</td><td><div class="table-item"><span class="mov-icon ' + esc(type) + '">' + iconText + '</span><span><span class="item-name">' + esc(itemName) + '</span><span class="item-sku">' + esc(sku) + (note ? " · " + esc(note) : "") + '</span></span></div></td><td><span class="badge plain ' + (type === "ingreso" ? "ok" : type === "consumo" ? "critical" : "neutral") + '">' + label + '</span></td><td class="mov-qty ' + (qty > 0 ? "positive" : qty < 0 ? "negative" : "") + '">' + (qty > 0 ? "+" : "") + quantity(qty) + '<small class="stock-change">' + quantity(m.stockBefore !== undefined ? m.stockBefore : m.stock_antes) + ' → ' + quantity(m.stockAfter !== undefined ? m.stockAfter : m.stock_despues) + '</small></td><td>' + (ref ? esc(ref) : '<span class="muted">—</span>') + '</td><td>' + (actor ? esc(actor) : '<span class="muted">—</span>') + '</td>' + (actions ? '<td><div class="actions-cell"><button class="table-action icon-only" aria-label="Editar movimiento" data-action="edit-movement" data-id="' + esc(m.id) + '"><span aria-hidden="true">✏️</span></button></div></td>' : '') + '</tr>';
      }).join("") : '<tr><td colspan="' + (actions ? 7 : 6) + '><div class="empty-state"><strong>Todavía no hay movimientos</strong>Registrá una entrada, un consumo o un ajuste para iniciar la trazabilidad.</div></td></tr>') +
      '</tbody></table></div>';
  }
  function filteredMovements() {
    let list = state.movements.slice();
    if (state.movementType !== "all") list = list.filter((m) => (m.type || m.tipo) === state.movementType);
    const q = state.movementSearch.toLowerCase().trim();
    if (q) list = list.filter((m) => ((m.itemName || m.item_name || "") + " " + (m.sku || "") + " " + (m.reference || m.referencia || "") + " " + (m.note || m.nota || "")).toLowerCase().includes(q));
    return list.sort((a, b) => new Date(b.createdAt || b.created_at) - new Date(a.createdAt || a.created_at));
  }
  function renderMovements() {
    const list = filteredMovements();
    return '<section class="panel table-panel"><div class="panel-head"><div><h2 class="panel-title">Historial de movimientos <span class="pill-count" id="movement-result-count">' + list.length + '</span></h2><p class="panel-caption">Los registros guardan el stock anterior y posterior al cambio.</p></div><button class="text-link" data-action="export-movements">Exportar CSV</button></div>' +
      '<div class="table-toolbar"><div class="search-wrap"><span class="search-icon">' + icon("search") + '</span><input id="movement-search" class="search-input" value="' + esc(state.movementSearch) + '" placeholder="Buscar material o referencia"></div>' +
      '<select id="movement-type-filter" class="filter-select" aria-label="Filtrar por tipo"><option value="all">Todos los movimientos</option><option value="ingreso"' + (state.movementType === "ingreso" ? " selected" : "") + '>Ingresos</option><option value="consumo"' + (state.movementType === "consumo" ? " selected" : "") + '>Consumos</option><option value="ajuste"' + (state.movementType === "ajuste" ? " selected" : "") + '>Ajustes</option></select></div><div id="movement-table-region">' + renderMovementTable(list, true) + '</div></section>';
  }
  function dateInputValue(date) {
    const localDate = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
    return localDate.toISOString().slice(0, 10);
  }
  function currentReportPeriod() {
    const now = new Date();
    const lastMonth = new Date(now);
    lastMonth.setDate(lastMonth.getDate() - 29);
    if (!state.reportFrom) state.reportFrom = dateInputValue(lastMonth);
    if (!state.reportTo) state.reportTo = dateInputValue(now);
    return { from: state.reportFrom, to: state.reportTo };
  }
  function calculatePeriodReport() {
    const period = currentReportPeriod();
    const movements = state.movements.filter((movement) => {
      const date = new Date(movement.createdAt || movement.created_at);
      if (Number.isNaN(date.getTime())) return false;
      const day = dateInputValue(date);
      return day >= period.from && day <= period.to;
    });
    const byItem = new Map();
    movements.forEach((movement) => {
      const sku = movement.sku || "";
      const name = movement.itemName || movement.item_name || "Material eliminado";
      const item = state.items.find((entry) => entry.sku === sku);
      const key = sku || name;
      if (!byItem.has(key)) byItem.set(key, { sku: sku, name: name, unit: item ? item.unit : "", entries: 0, consumption: 0, adjustment: 0, count: 0 });
      const row = byItem.get(key);
      const type = movement.type || movement.tipo;
      const amount = num(movement.quantity !== undefined ? movement.quantity : movement.cantidad);
      row.count++;
      if (type === "ingreso") row.entries += Math.abs(amount);
      else if (type === "consumo") row.consumption += Math.abs(amount);
      else row.adjustment += amount;
    });
    const rows = Array.from(byItem.values()).sort((a, b) => b.count - a.count || a.name.localeCompare(b.name, "es"));
    return {
      from: period.from, to: period.to, movements: movements,
      entries: movements.filter((m) => (m.type || m.tipo) === "ingreso").length,
      consumptions: movements.filter((m) => (m.type || m.tipo) === "consumo").length,
      adjustments: movements.filter((m) => (m.type || m.tipo) === "ajuste").length,
      rows: rows
    };
  }
  function renderReports() {
    const report = calculatePeriodReport();
    const periodText = report.from + " a " + report.to;
    const bodyRows = report.rows.length ? report.rows.map((row) =>
      '<tr><td><div class="table-item"><span><span class="item-name">' + esc(row.name) + '</span><span class="item-sku">' + esc(row.sku) + '</span></span></div></td>' +
      '<td>' + esc(row.unit || "—") + '</td><td>' + quantity(row.entries) + '</td><td>' + quantity(row.consumption) + '</td><td>' + row.count + '</td></tr>'
    ).join("") : '<tr><td colspan="5"><div class="empty-state"><strong>No hay movimientos en este período</strong>Probá elegir otro rango de fechas.</div></td></tr>';
    return '<section class="panel report-filter-panel"><div class="panel-head"><div><h2 class="panel-title">Período del reporte</h2></div></div>' +
      '<div class="report-filter-row"><label class="report-date-field">Desde<input id="report-from" type="date" value="' + esc(report.from) + '"></label><label class="report-date-field">Hasta<input id="report-to" type="date" value="' + esc(report.to) + '"></label><button class="button button-dark" type="button" data-action="apply-report-period">Aplicar período</button></div></section>' +
      '<div class="kpi-grid report-kpis">' +
      kpi("MOVIMIENTOS", report.movements.length, periodText, "arrows", "blue") +
      kpi("INGRESOS", report.entries, "Operaciones de entrada", "upload", "lime") +
      kpi("CONSUMOS", report.consumptions, "Operaciones de salida", "box", "alert") +
      kpi("AJUSTES", report.adjustments, "Conteos y correcciones", "settings", "") +
      '</div><section class="panel table-panel"><div class="panel-head"><div><h2 class="panel-title">Detalle por material <span class="pill-count">' + report.rows.length + '</span></h2></div></div><div class="table-scroll"><table class="data-table"><thead><tr><th>MATERIAL</th><th>UNIDAD</th><th>INGRESOS</th><th>CONSUMOS</th><th>MOV.</th></tr></thead><tbody>' + bodyRows + '</tbody></table></div></section>';
  }
  function exportPeriodReport() {
    const report = calculatePeriodReport();
    const headers = ["codigo","material","unidad","ingresos","consumos","movimientos"];
    const rows = report.rows.map((row) => [row.sku,row.name,row.unit,row.entries,row.consumption,row.count]);
    downloadCSV("vialseg-reporte-" + report.from + "_a_" + report.to + ".csv", headers, rows);
  }


  function costChart(points, field, title, currency, color) {
    const values = points.map((p) => num(p[field])).filter((v) => v > 0);
    if (!values.length) return '<section class="panel cost-chart"><div class="panel-head"><div><h2 class="panel-title">' + title + '</h2><p class="panel-caption">Precio unitario registrado en cada ingreso.</p></div></div><div class="empty-state"><strong>Sin precios registrados</strong>Los nuevos ingresos aparecerán en este gráfico.</div></section>';
    const width = 680, height = 260, left = 62, right = 96, top = 18, bottom = 42;
    const min = Math.min(...values), max = Math.max(...values), span = max - min || Math.max(1, max * 0.1);
    const xy = points.map((p, i) => {
      const x = points.length === 1 ? width / 2 : left + i * (width - left - right) / (points.length - 1);
      const y = top + (max - num(p[field])) * (height - top - bottom) / span;
      return [x, y];
    });
    const line = xy.map((p) => p.join(",")).join(" ");
    const ticks = [0, .5, 1].map((ratio) => {
      const y = top + ratio * (height - top - bottom);
      const value = max - ratio * span;
      return '<line x1="' + left + '" y1="' + y + '" x2="' + (width-right) + '" y2="' + y + '" stroke="#e8edf2"/><text x="' + (left-8) + '" y="' + (y+4) + '" text-anchor="end" fill="#8793a4" font-size="11">' + esc(currency(value)) + '</text>';
    }).join("");
    const chartDate = (value) => { const d = new Date(value); if (Number.isNaN(d.getTime())) return "—"; const parts = new Intl.DateTimeFormat("es-AR", { month: "short", year: "numeric" }).formatToParts(d); const month = parts.find((part) => part.type === "month").value.replace(".", "").toUpperCase(); const year = parts.find((part) => part.type === "year").value; return month + " " + year; };
    const start = chartDate(points[0].created_at || points[0].createdAt), end = chartDate(points[points.length-1].created_at || points[points.length-1].createdAt);
    return '<section class="panel cost-chart"><div class="panel-head"><div><h2 class="panel-title">' + title + '</h2><p class="panel-caption">' + points.length + ' ingresos con precio registrado</p></div></div><div class="chart-scroll"><svg viewBox="0 0 ' + width + ' ' + height + '" role="img" aria-label="' + esc(title) + '">' + ticks + '<polyline points="' + line + '" fill="none" stroke="' + color + '" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>' + xy.map((p,i) => '<circle cx="' + p[0] + '" cy="' + p[1] + '" r="4" fill="' + color + '"><title>' + esc(shortDate(points[i].created_at || points[i].createdAt) + " · " + currency(points[i][field])) + '</title></circle>').join("") + '<text x="' + left + '" y="' + (height-10) + '" fill="#8793a4" font-size="11">' + esc(start) + '</text><text x="' + (width-right) + '" y="' + (height-10) + '" text-anchor="end" fill="#8793a4" font-size="11">' + esc(end) + '</text></svg></div></section>';
  }
  function renderCostAnalysis() {
    const items = activeItems().slice().sort((a, b) => String(a.sku || "").localeCompare(String(b.sku || ""), "es", { numeric: true, sensitivity: "base" }));
    if (!items.length) return '<section class="panel"><div class="empty-state"><strong>No hay materiales</strong>Agregá materiales al catálogo para analizar sus precios.</div></section>';
    if (!items.some((i) => String(i.id) === String(state.priceHistoryItem))) state.priceHistoryItem = String(items[0].id);
    const selected = items.find((i) => String(i.id) === String(state.priceHistoryItem));
    const options = "";
    const points = state.mode === "demo" ? state.movements.filter((m) => String(m.itemId) === String(selected.id) && m.type === "ingreso" && num(m.unitCostArs) > 0).sort((a,b) => new Date(a.createdAt)-new Date(b.createdAt)) : state.priceHistoryData;
    const ars = (v) => new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 2 }).format(num(v));
    return '<section class="panel cost-filter"><div class="panel-head"><div><h2 class="panel-title">Evolución del costo unitario</h2><p class="panel-caption">Cada punto corresponde a un precio ingresado al registrar una compra.</p></div></div><div class="report-filter-row"><label class="report-date-field">Material<div class="material-picker"><input id="price-history-item" type="search" value="' + esc(selected.sku + " · " + selected.name) + '" placeholder="Buscar por nombre o código" autocomplete="off" role="combobox" aria-autocomplete="list" aria-controls="price-history-results" aria-expanded="false"><div id="price-history-results" class="material-suggestions" role="listbox" hidden></div></div></label><div class="cost-current"><span>Último costo guardado</span><strong>' + ars(selected.unitCost) + ' / ' + moneyUSD(selected.avgCostUsd) + '</strong></div></div></section>' +
      '<div class="cost-chart-grid">' + costChart(points, "unitCostArs", "Precio unitario en ARS", ars, "#0795b8") + costChart(points, "unitCostUsd", "Precio unitario en USD", moneyUSD, "#79bd32") + '</div>' +
      '<p class="cost-note">El equivalente en USD se calcula con la cotización vendedora del dólar blue guardada para cada ingreso.</p>';
  }
  async function loadPriceHistory(itemId) {
    if (!itemId) return;
    state.priceHistoryItem = String(itemId);
    if (state.mode === "demo") { render(); return; }
    state.priceHistoryData = [];
    if (state.view === "costs") render();
    const rows = await api("inventory_movements?select=created_at,precio_unitario_ars,precio_unitario_usd,cotizacion_blue,cotizacion_fecha,cotizacion_fuente&item_id=eq." + encodeURIComponent(itemId) + "&tipo=eq.ingreso&precio_unitario_usd=not.is.null&order=created_at.asc&limit=1000");
    state.priceHistoryData = (rows || []).map((row) => ({ created_at: row.cotizacion_fecha || row.created_at, unitCostArs: num(row.precio_unitario_ars), unitCostUsd: num(row.precio_unitario_usd), blueRate: num(row.cotizacion_blue), quoteSource: row.cotizacion_fuente }));
    if (state.view === "costs") render();
  }
  function renderReplenishment() {
    const abc = withAbc(activeItems());
    const classOrder = { A: 0, B: 1, C: 2 };
    const list = candidates().sort((a, b) => {
      const byClass = classOrder[abc[a.id] || "C"] - classOrder[abc[b.id] || "C"];
      return byClass || String(a.sku || "").localeCompare(String(b.sku || ""), "es", { numeric: true, sensitivity: "base" });
    });
    const totalCritical = criticalItems().length;
    const noRestock = activeItems().filter((item) => !item.replenish && num(item.stock) <= num(item.safetyStock));
    return '<div class="replenishment-summary"><article class="summary-card"><span>Materiales para reponer</span><strong>' + list.length + '</strong></article><article class="summary-card"><span>Bajo stock de seguridad</span><strong>' + totalCritical + '</strong></article><article class="summary-card"><span>Sin reposición y bajo umbral</span><strong>' + noRestock.length + '</strong></article></div>' +
      (noRestock.length ? '<section class="panel" style="margin-bottom:15px"><div class="panel-head"><div><h2 class="panel-title">Materiales sin reposición</h2><p class="panel-caption">Se muestran para seguimiento; el sistema no sugiere una compra automática.</p></div></div><div class="attention-list">' + noRestock.map((item) => '<div class="attention-row"><span class="attention-icon amber">' + icon("alert") + '</span><div class="attention-copy"><strong>' + esc(item.name) + '</strong><small>' + esc(item.sku) + ' · Definir alternativa de abastecimiento</small></div><div class="attention-stock">' + quantity(item.stock) + ' ' + esc(item.unit) + '<small>stock actual</small></div></div>').join("") + '</div></section>' : '') +
      '<section class="panel table-panel"><div class="panel-head"><div><h2 class="panel-title">Materiales para reponer</h2><p class="panel-caption">La cantidad cubre lo que falta hasta el punto de pedido o el lote mínimo exigido por el proveedor, si es mayor.</p></div></div>' +
      (list.length ? list.map((item) => '<article class="reorder-card"><div class="reorder-main"><div class="reorder-name">' + esc(item.name) + '</div><div class="reorder-meta">' + esc(item.sku) + ' · ' + esc(item.supplier || "Proveedor sin registrar") + '</div></div><div class="reorder-abc-column"><span class="class-badge abc-' + (abc[item.id] || "C").toLowerCase() + '">' + (abc[item.id] || "C") + '</span></div><div class="reorder-value"><span>' + quantity(item.stock) + ' ' + esc(item.unit) + '</span><small>Stock actual</small></div><div class="reorder-value"><span>' + quantity(reorderPoint(item)) + ' ' + esc(item.unit) + '</span><small>Punto de pedido</small></div><div class="reorder-value"><span class="reorder-qty">' + quantity(minimumOrderQuantity(item)) + ' ' + esc(item.unit) + '</span><small>Cantidad a pedir</small></div><div class="reorder-action"><button class="button button-outline button-small" data-action="new-movement" data-id="' + esc(item.id) + '" data-kind="ingreso" data-quantity="' + esc(minimumOrderQuantity(item)) + '">Registrar ingreso</button></div></article>').join("") : '<div class="reorder-none"><strong>No hay reposiciones pendientes</strong>Los materiales reponibles están por encima de su punto de pedido.</div>')
  }

  function toast(message, type) {
    const root = $("#toast-root");
    const el = document.createElement("div");
    el.className = "toast " + (type || "success");
    el.textContent = message;
    root.appendChild(el);
    setTimeout(() => el.remove(), 3500);
  }
  function openModal(title, subtitle, body, foot, wide) {
    $("#modal-root").innerHTML = '<div class="modal-backdrop" data-close-modal><section class="modal ' + (wide ? "wide" : "") + '" role="dialog" aria-modal="true" aria-labelledby="modal-title"><header class="modal-head"><div><h2 id="modal-title" class="modal-title">' + title + '</h2><p class="modal-subtitle">' + subtitle + '</p></div><button class="modal-close" type="button" data-close-modal aria-label="Cerrar">×</button></header><div class="modal-body">' + body + '</div>' + (foot || "") + '</section></div>';
    const first = $("input,select,button", $(".modal"));
    if (first) setTimeout(() => first.focus(), 30);
  }
  function closeModal() { $("#modal-root").innerHTML = ""; }
  function modalFoot(label, action) {
    return '<footer class="modal-foot"><button class="button button-outline" type="button" data-close-modal>Cancelar</button><button class="button button-dark" type="submit" form="' + action + '">' + label + '</button></footer>';
  }
  function val(id) { const el = $("#" + id); return el ? el.value.trim() : ""; }
  function itemById(id) { return state.items.find((item) => String(item.id) === String(id)); }

  function showItemModal(id) {
    const item = id ? itemById(id) : null;
    const isEdit = Boolean(item);
    const body = '<form id="item-form"><div class="form-grid">' +
      field("Código", '<input id="f-sku" required maxlength="40" value="' + esc(item ? item.sku : "") + '" placeholder="Ej. EL-1042">') +
      field("Nombre del material", '<input id="f-name" required maxlength="120" value="' + esc(item ? item.name : "") + '" placeholder="Nombre descriptivo">') +
      field("Categoría", '<input id="f-category" required value="' + esc(item ? item.category : "General") + '" placeholder="Electrónica, cableado…">') +
      field("Unidad de medida", '<input id="f-unit" required value="' + esc(item ? item.unit : "u") + '" placeholder="u, m, kg…">') +
      field("Costo unitario (ARS)", '<input id="f-cost" type="number" min="0" step="0.01" value="' + esc(item ? item.unitCost : 0) + '">') +
      field("Consumo mensual promedio", '<input id="f-use" type="number" min="0" step="0.01" value="' + esc(item ? item.monthlyUse : 0) + '">') +
      field("Stock de seguridad", '<input id="f-safety" type="number" min="0" step="0.01" value="' + esc(item ? item.safetyStock : 0) + '">') +
      field("Plazo del proveedor (días)", '<input id="f-lead" type="number" min="0" step="1" value="' + esc(item ? item.leadDays : 0) + '">') +
      field("Lote mínimo del proveedor", '<input id="f-minimum-lot" type="number" min="0" step="0.01" value="' + esc(item ? item.minimumLot : 0) + '" placeholder="0 si no aplica"><small>Mínimo indicado por el proveedor; dejalo en 0 si no existe.</small>') +
      field("Proveedor", '<input id="f-supplier" value="' + esc(item ? item.supplier : "") + '" placeholder="Proveedor habitual">') +
      field("Ubicación física", '<input id="f-location" value="' + esc(item ? item.location : "") + '" placeholder="Depósito, estante…">') +
      (isEdit ? '<div class="field full"><div class="form-info">El stock actual es ' + quantity(item.stock) + ' ' + esc(item.unit) + '. Para modificarlo, registrá un movimiento y conservá el historial.</div></div>' : field("Stock inicial", '<input id="f-stock" type="number" min="0" step="0.01" value="0"><small>Se guardará como un ajuste inicial auditable.</small>')) +
      '<div class="field full"><label class="checkbox-line"><input id="f-replenish" type="checkbox"' + (item ? (item.replenish ? " checked" : "") : " checked") + '> Este material se repone regularmente</label></div>' +
      '</div></form>';
    openModal(isEdit ? "Editar material" : "Nuevo material", isEdit ? "Actualizá los datos y parámetros de reposición." : "Agregá el material al catálogo de inventario.", body, modalFoot(isEdit ? "Guardar cambios" : "Crear material", "item-form"), true);
    $("#item-form").dataset.id = item ? item.id : "";
  }
  function field(label, inputHtml) { return '<div class="field"><label>' + label + '</label>' + inputHtml + '</div>'; }

  function showMovementModal(id, kind, presetQuantity) {
    const items = activeItems().slice().sort((a, b) => String(a.sku || "").localeCompare(String(b.sku || ""), "es", { numeric: true, sensitivity: "base" }));
    if (!items.length) { toast("Primero agregá un material al catálogo.", "error"); return; }
    const selected = id ? itemById(id) : items[0];
    const options = items.map((item) => '<option value="' + esc(item.id) + '"' + (selected && String(item.id) === String(selected.id) ? " selected" : "") + '>' + esc(item.sku + " · " + item.name) + '</option>').join("");
    const selectedLabel = selected ? selected.sku + " · " + selected.name : "";
    const typeOptions = [["ingreso","Ingreso de stock"],["consumo","Consumo / salida"],["ajuste","Ajuste por conteo físico"]].map((x) => '<option value="' + x[0] + '"' + (kind === x[0] ? " selected" : "") + '>' + x[1] + '</option>').join("");
    const body = '<form id="movement-form"><div class="form-grid">' +
      field("Material", '<div class="material-picker"><input id="m-item-search" type="search" autocomplete="off" role="combobox" aria-autocomplete="list" aria-controls="m-item-results" aria-expanded="false" value="' + esc(selectedLabel) + '" placeholder="Escribí nombre o código"><div id="m-item-results" class="material-suggestions" role="listbox" hidden></div><select id="m-item" hidden>' + options + '</select></div>') +
      field("Tipo de movimiento", '<select id="m-type">' + typeOptions + '</select>') +
      field('<span id="m-quantity-label">Cantidad</span>', '<input id="m-quantity" type="number" min="0" step="0.01" required placeholder="0" value="' + (presetQuantity == null ? "" : esc(presetQuantity)) + '">') +
      '<div class="field full" id="m-unit-cost-field" hidden><label for="m-unit-cost-ars">Precio pagado por unidad (ARS)</label><input id="m-unit-cost-ars" type="number" min="0.01" step="0.01" placeholder="0,00"><small id="m-blue-quote-note" class="field-hint">Se convertirá a USD con el dólar blue vendedor al registrar el ingreso.</small></div>' +
      field("Referencia (opcional)", '<input id="m-reference" maxlength="80" placeholder="N.º de OC, OT, factura o ticket"><small>Identifica el comprobante relacionado; no se completa automáticamente.</small>') +
      '<div class="field full">' + '<label for="m-note">Motivo o detalle</label><textarea id="m-note" required maxlength="300" placeholder="Dejá una nota breve para mantener la trazabilidad"></textarea></div>' +
      '<div class="field full"><div class="form-info" id="movement-help"></div></div></div></form>';
    openModal("Registrar movimiento", "El cambio de stock quedará asociado a una fecha y responsable.", body, modalFoot("Guardar movimiento", "movement-form"), false);
    updateMovementHelp();
  }
  function showEditMovementModal(id) {
    const movement = state.movements.find((entry) => String(entry.id) === String(id));
    if (!movement) { toast("No se encontró el movimiento.", "error"); return; }
    const reference = movement.reference || movement.referencia || "";
    const note = movement.note || movement.nota || "";
    const body = '<form id="edit-movement-form"><div class="form-grid">' +
      field("Referencia", '<input id="edit-movement-reference" maxlength="80" value="' + esc(reference) + '" placeholder="OC, OT, factura o comprobante">') +
      '<div class="field full"><label for="edit-movement-note">Motivo o detalle</label><textarea id="edit-movement-note" required maxlength="300">' + esc(note) + '</textarea></div>' +
      '<div class="field full"><div class="form-info">Desde aquí podés corregir la referencia y el detalle. El tipo, la cantidad y el stock registrado se conservan.</div></div>' +
      '</div></form>';
    openModal("Editar movimiento", "Corregí los datos de referencia del registro.", body, modalFoot("Guardar cambios", "edit-movement-form"), false);
    $("#edit-movement-form").dataset.id = movement.id;
  }
  function renderCostItemSuggestions(query) {
    const results = $("#price-history-results");
    const input = $("#price-history-item");
    if (!results || !input) return;
    const q = String(query || "").trim().toLocaleLowerCase("es");
    const items = activeItems().slice().sort((a, b) => String(a.sku || "").localeCompare(String(b.sku || ""), "es", { numeric: true, sensitivity: "base" }));
    const matches = q ? items.filter((item) => (String(item.sku || "") + " " + String(item.name || "")).toLocaleLowerCase("es").includes(q)) : items;
    results.innerHTML = matches.length ? matches.map((item) => '<button type="button" class="material-suggestion" role="option" data-cost-item-id="' + esc(item.id) + '"><span><strong>' + esc(item.sku) + '</strong><span>' + esc(item.name) + '</span></span></button>').join("") : '<div class="material-suggestion-empty">No hay materiales que coincidan.</div>';
    results.hidden = false;
    input.setAttribute("aria-expanded", "true");
  }
  function hideCostItemSuggestions() {
    const results = $("#price-history-results"), input = $("#price-history-item");
    if (results) results.hidden = true;
    if (input) input.setAttribute("aria-expanded", "false");
  }
  function selectCostItem(id) {
    const item = activeItems().find((candidate) => String(candidate.id) === String(id));
    if (!item) return;
    state.priceHistoryItem = String(item.id);
    hideCostItemSuggestions();
    loadPriceHistory(item.id).catch((error) => toast(error.message || "No se pudo cargar el historial de precios.", "error"));
  }
  function renderMovementItemSuggestions(query) {
    const results = $("#m-item-results");
    const input = $("#m-item-search");
    if (!results || !input) return;
    const q = String(query || "").trim().toLocaleLowerCase("es");
    const items = activeItems().slice().sort((a, b) => String(a.sku || "").localeCompare(String(b.sku || ""), "es", { numeric: true, sensitivity: "base" }));
    const matches = q ? items.filter((item) => (String(item.sku || "") + " " + String(item.name || "")).toLocaleLowerCase("es").includes(q)) : items;
    results.innerHTML = matches.length ? matches.map((item) => '<button type="button" class="material-suggestion" role="option" data-movement-item-id="' + esc(item.id) + '"><span><strong>' + esc(item.sku) + '</strong><span>' + esc(item.name) + '</span></span><small>Stock: ' + esc(quantity(item.stock)) + ' ' + esc(item.unit) + '</small></button>').join("") : '<div class="material-suggestion-empty">No hay materiales que coincidan.</div>';
    results.hidden = false;
    input.setAttribute("aria-expanded", "true");
  }
  function hideMovementItemSuggestions() {
    const results = $("#m-item-results"), input = $("#m-item-search");
    if (results) results.hidden = true;
    if (input) input.setAttribute("aria-expanded", "false");
  }
  function selectMovementItem(id) {
    const item = itemById(id);
    if (!item) return;
    $("#m-item").value = item.id;
    $("#m-item-search").value = item.sku + " · " + item.name;
    hideMovementItemSuggestions();
    updateMovementHelp();
  }
  function updateMovementHelp() {
    const selected = itemById($("#m-item") && $("#m-item").value);
    if (!selected) { const help = $("#movement-help"); if (help) help.textContent = "Buscá y seleccioná un material para continuar."; const cost = $("#m-unit-cost-field"); if (cost) cost.hidden = true; const price = $("#m-unit-cost-ars"); if (price) price.required = false; const quantityInput = $("#m-quantity"); if (quantityInput) { quantityInput.max = ""; quantityInput.placeholder = "0"; } return; }
    const type = $("#m-type").value;
    $("#m-quantity-label").textContent = type === "ajuste" ? "Nuevo stock contado" : "Cantidad";
    $("#m-quantity").placeholder = type === "ajuste" ? quantity(selected.stock) : "0";
    $("#m-quantity").max = type === "consumo" ? String(selected.stock) : "";
    $("#m-unit-cost-field").hidden = type !== "ingreso";
    $("#m-unit-cost-ars").required = type === "ingreso";
    $("#movement-help").textContent = type === "ingreso" ? "Stock actual: " + quantity(selected.stock) + " " + selected.unit + ". La cantidad se suma; se guarda el precio pagado en ARS y su equivalente en USD." :
      type === "consumo" ? "Stock actual: " + quantity(selected.stock) + " " + selected.unit + ". No se permite consumir más de lo disponible." :
      "Stock actual: " + quantity(selected.stock) + " " + selected.unit + ". Ingresá el resultado del conteo; se registra la diferencia.";
  }
  function showSettings() {
    const body = '<div class="form-info"><strong>Modo actual:</strong> ' + (state.mode === "demo" ? "demostración local, con datos ficticios" : "base compartida de inventario") + '</div>' +
      '<h3 class="panel-title" style="margin:16px 0 7px">Punto de reposición</h3><p class="panel-caption">Stock de seguridad + consumo mensual / 30 × plazo del proveedor en días.</p>' +
      '<h3 class="panel-title" style="margin:16px 0 7px">Cantidad sugerida</h3><p class="panel-caption">Busca cubrir el punto de reposición y un lote adicional, redondeando al múltiplo del lote configurado.</p>' +
      '<h3 class="panel-title" style="margin:16px 0 7px">Clasificación ABC</h3><p class="panel-caption">Valor anual de consumo (unidades mensuales × 12 × costo unitario): clase A hasta el 80% acumulado, B hasta el 95% y C para el resto.</p>' +
      '<div class="form-info" style="margin-top:16px">Estos criterios son una base inicial para validar con Vialseg.</div>';
    openModal("Criterios y configuración", "Reglas de cálculo visibles para revisar antes de usar el sistema.", body, '<footer class="modal-foot"><button class="button button-dark" type="button" data-close-modal>Cerrar</button></footer>', false);
  }

  function showLoading(label) {
    const el = document.createElement("div");
    el.className = "loading-cover";
    el.innerHTML = '<div class="loading-box"><span class="spinner"></span>' + esc(label || "Guardando cambios…") + '</div>';
    document.body.appendChild(el);
    return () => el.remove();
  }
  async function persistItem(item, isNew, initialStock) {
    if (state.mode === "demo") {
      const current = itemById(item.id);
      if (current) Object.assign(current, item, { updatedAt: new Date().toISOString() });
      else state.items.push(item);
      persistDemo();
      if (isNew && num(initialStock) > 0) {
        if (!(num(item.unitCost) > 0)) throw new Error("Ingresá el costo unitario en ARS para registrar el stock inicial.");
        const quote = await fetchBlueQuote();
        await addMovement({ itemId: item.id, type: "ingreso", quantity: num(initialStock), unitCostArs: num(item.unitCost), blueRate: quote.rate, unitCostUsd: num(item.unitCost) / quote.rate, quoteAt: quote.at, quoteSource: quote.source, note: "Stock inicial del alta", reference: "ALTA", actor: state.user.name, suppressRender: true });
      }
      return item;
    }
    const payload = itemToRow(item);
    let rows;
    if (isNew) {
      if (num(initialStock) > 0) payload.stock = 0;
      rows = await api("inventory_items?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
      let savedRow = Array.isArray(rows) ? rows[0] : null;
      if (!savedRow) {
        const matches = await api("inventory_items?select=*&sku=eq." + encodeURIComponent(item.sku) + "&limit=1");
        savedRow = Array.isArray(matches) ? matches[0] : null;
      }
      if (!savedRow) throw new Error("Supabase no devolvió el material guardado. Revisá la conexión y los permisos de lectura de inventory_items.");
      const saved = itemFromRow(savedRow);
      state.items.push(saved);
      if (num(initialStock) > 0) {
        if (!(num(item.unitCost) > 0)) throw new Error("Ingresá el costo unitario en ARS para registrar el stock inicial.");
        const quote = await fetchBlueQuote();
        await addMovement({ itemId: saved.id, type: "ingreso", quantity: num(initialStock), unitCostArs: num(item.unitCost), blueRate: quote.rate, unitCostUsd: num(item.unitCost) / quote.rate, quoteAt: quote.at, quoteSource: quote.source, note: "Stock inicial del alta", reference: "ALTA", actor: currentActor(), suppressRender: true });
      }
      return saved;
    }
    await api("inventory_items?id=eq." + encodeURIComponent(item.id), { method: "PATCH", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
    const idx = state.items.findIndex((x) => String(x.id) === String(item.id));
    if (idx >= 0) state.items[idx] = item;
    return item;
  }
  async function addMovement(data) {
    const item = itemById(data.itemId);
    if (!item) throw new Error("No se encontró el material.");
    const amount = num(data.quantity);
    if (amount < 0) throw new Error("La cantidad no puede ser negativa.");
    let delta;
    if (data.type === "ingreso") {
      if (amount <= 0) throw new Error("El ingreso debe ser mayor que cero.");
      delta = amount;
    } else if (data.type === "consumo") {
      if (amount <= 0) throw new Error("El consumo debe ser mayor que cero.");
      if (amount > num(item.stock)) throw new Error("El consumo supera el stock disponible.");
      delta = -amount;
    } else if (data.type === "ajuste") {
      delta = amount - num(item.stock);
    } else throw new Error("Tipo de movimiento no válido.");
    if (data.type === "ingreso" && (!(data.unitCostArs > 0) || !(data.blueRate > 0) || !(data.unitCostUsd > 0))) throw new Error("El ingreso necesita precio en ARS y cotización blue.");
    const before = num(item.stock);
    const after = before + delta;
    if (after < 0) throw new Error("El ajuste no puede dejar stock negativo.");
    if (state.mode === "demo") {
      item.stock = after;
      item.updatedAt = new Date().toISOString();
      if (data.type === "ingreso") { item.avgCostUsd = after > 0 ? ((before * num(item.avgCostUsd)) + amount * data.unitCostUsd) / after : data.unitCostUsd; item.unitCost = data.unitCostArs; item.quoteRate = data.blueRate; }
      state.movements.unshift({ id: "demo-m-" + Date.now(), itemId: item.id, sku: item.sku, itemName: item.name, type: data.type, quantity: delta, stockBefore: before, stockAfter: after, note: data.note || "", reference: data.reference || "", actor: data.actor || state.user.name || "Administración", createdAt: new Date().toISOString(), unitCostArs: data.unitCostArs, unitCostUsd: data.unitCostUsd, blueRate: data.blueRate, quoteAt: data.quoteAt, quoteSource: data.quoteSource });
      persistDemo();
    } else {
      await api("rpc/registrar_movimiento", { method: "POST", body: JSON.stringify({ p_item_id: item.id, p_tipo: data.type, p_cantidad: amount, p_nota: data.note || "", p_referencia: data.reference || "", p_actor: data.actor || currentActor(), p_precio_unitario_ars: data.unitCostArs || null, p_precio_unitario_usd: data.unitCostUsd || null, p_cotizacion_blue: data.blueRate || null, p_cotizacion_fecha: data.quoteAt || null, p_cotizacion_fuente: data.quoteSource || null }) });
      if (data.type === "ingreso") { item.avgCostUsd = after > 0 ? ((before * num(item.avgCostUsd)) + amount * data.unitCostUsd) / after : data.unitCostUsd; item.unitCost = data.unitCostArs; item.quoteRate = data.blueRate; }
      item.stock = after;
      item.updatedAt = new Date().toISOString();
      await loadRemoteMovements();
    }
    if (!data.suppressRender) render();
  }
  async function loadRemoteMovements() {
    const rows = await api("inventory_movements?select=*&order=created_at.desc&limit=500");
    state.movements = (rows || []).map(movementFromRow);
  }

  function getItemForm() {
    const sku = val("f-sku");
    const name = val("f-name");
    const category = val("f-category");
    const unit = val("f-unit");
    const minimumLot = num(val("f-minimum-lot"));
    if (!sku || !name || !category || !unit) throw new Error("Completá los datos obligatorios.");
    if (minimumLot < 0) throw new Error("El lote mínimo del proveedor no puede ser negativo.");
    const id = $("#item-form").dataset.id;
    const existing = id ? itemById(id) : null;
    const duplicate = state.items.find((x) => x.sku.toLowerCase() === sku.toLowerCase() && String(x.id) !== String(id));
    if (duplicate) throw new Error("Ya existe un material con ese código.");
    const item = {
      id: id || "demo-i-" + Date.now(), sku: sku, name: name, category: category, unit: unit,
      stock: existing ? num(existing.stock) : 0, unitCost: num(val("f-cost")), avgCostUsd: existing ? num(existing.avgCostUsd) : 0, quoteRate: existing ? num(existing.quoteRate) : 0, monthlyUse: num(val("f-use")),
      safetyStock: num(val("f-safety")), leadDays: num(val("f-lead")), minimumLot: minimumLot,
      supplier: val("f-supplier"), location: val("f-location"), replenish: $("#f-replenish").checked, active: true, updatedAt: new Date().toISOString()
    };
    return { item: item, isNew: !existing, initialStock: isEditStockForm() ? 0 : num(val("f-stock")) };
  }
  function isEditStockForm() { return !$("#f-stock"); }

  async function deleteItem(id) {
    const item = itemById(id);
    if (!item) return;
    const confirmed = window.confirm("¿Eliminar \"" + item.name + "\" del catálogo? Los movimientos registrados se conservarán en el historial.");
    if (!confirmed) return;
    const loading = showLoading("Eliminando material…");
    try {
      if (state.mode === "demo") {
        state.items = state.items.filter((entry) => String(entry.id) !== String(id));
        persistDemo();
      } else {
        await api("inventory_items?id=eq." + encodeURIComponent(id), { method: "DELETE" });
        state.items = state.items.filter((entry) => String(entry.id) !== String(id));
      }
      render();
      toast("Material eliminado del catálogo.");
    } catch (error) {
      toast(error.message || "No se pudo eliminar el material.", "error");
    } finally { loading(); }
  }

  async function submitItemForm(form) {
    const loading = showLoading("Guardando material…");
    try {
      const values = getItemForm();
      await persistItem(values.item, values.isNew, values.initialStock);
      closeModal();
      render();
      toast(values.isNew ? "Material agregado al inventario." : "Cambios guardados.");
    } catch (error) { toast(error.message || "No se pudo guardar el material.", "error"); }
    finally { loading(); }
  }
  async function submitEditMovementForm(form) {
    const movementId = form.dataset.id;
    const note = val("edit-movement-note").trim();
    const reference = val("edit-movement-reference").trim();
    if (!note) { toast("Ingresá el motivo o detalle del movimiento.", "error"); return; }
    const loading = showLoading("Guardando cambios…");
    try {
      const movement = state.movements.find((entry) => String(entry.id) === String(movementId));
      if (!movement) throw new Error("No se encontró el movimiento.");
      if (state.mode === "demo") {
        movement.note = note;
        movement.reference = reference;
        persistDemo();
      } else {
        await api("rpc/editar_datos_movimiento", { method: "POST", body: JSON.stringify({ p_movimiento_id: movementId, p_nota: note, p_referencia: reference }) });
        movement.note = note;
        movement.reference = reference;
      }
      closeModal();
      render();
      toast("Referencia y detalle actualizados.");
    } catch (error) { toast(error.message || "No se pudo editar el movimiento.", "error"); }
    finally { loading(); }
  }
  async function submitMovementForm() {
    const loading = showLoading("Registrando movimiento…");
    try {
      const itemId = $("#m-item").value;
      if (!itemId) throw new Error("Buscá y seleccioná un material antes de guardar.");
      const type = $("#m-type").value;
      const amount = val("m-quantity");
      const note = val("m-note");
      if (amount === "" || !note) throw new Error("Ingresá la cantidad y el motivo del movimiento.");
      let purchaseCost = {};
      if (type === "ingreso") {
        const ars = num(val("m-unit-cost-ars"));
        if (!(ars > 0)) throw new Error("Ingresá el precio pagado por unidad en ARS.");
        const quote = await fetchBlueQuote();
        purchaseCost = { unitCostArs: ars, blueRate: quote.rate, unitCostUsd: ars / quote.rate, quoteAt: quote.at, quoteSource: quote.source };
      }
      await addMovement(Object.assign({ itemId: itemId, type: type, quantity: num(amount), note: note, reference: val("m-reference"), actor: currentActor() || state.user.name }, purchaseCost));
      closeModal();
      render();
      toast("Movimiento registrado y stock actualizado.");
    } catch (error) { toast(error.message || "No se pudo registrar el movimiento.", "error"); }
    finally { loading(); }
  }

  function csvCell(value) {
    const s = String(value == null ? "" : value);
    return '"' + s.replace(/"/g, '""') + '"';
  }
  function downloadCSV(filename, headers, rows) {
    const content = "\uFEFF" + [headers.map(csvCell).join(","), ...rows.map((r) => r.map(csvCell).join(","))].join("\r\n");
    const url = URL.createObjectURL(new Blob([content], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a"); a.href = url; a.download = filename; a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  function exportItems() {
    const headers = ["codigo","nombre","categoria","unidad","stock","costo_unitario","consumo_mensual","stock_seguridad","plazo_dias","lote_minimo","proveedor","ubicacion","se_repone"];
    downloadCSV("vialseg-materiales.csv", headers, activeItems().map((i) => [i.sku,i.name,i.category,i.unit,i.stock,i.unitCost,i.monthlyUse,i.safetyStock,i.leadDays,i.minimumLot,i.supplier,i.location,i.replenish ? "si" : "no"]));
  }
  function exportMovements() {
    const headers = ["fecha","codigo","material","tipo","cantidad","stock_antes","stock_despues","referencia","motivo","responsable"];
    downloadCSV("vialseg-movimientos.csv", headers, state.movements.map((m) => [m.createdAt || m.created_at,m.sku,m.itemName || m.item_name,m.type || m.tipo,m.quantity !== undefined ? m.quantity : m.cantidad,m.stockBefore !== undefined ? m.stockBefore : m.stock_antes,m.stockAfter !== undefined ? m.stockAfter : m.stock_despues,m.reference || m.referencia,m.note || m.nota,actorLabel(m.actor)]));
  }
  function downloadTemplate() {
    const headers = ["codigo","nombre","categoria","unidad","stock","costo_unitario","consumo_mensual","stock_seguridad","plazo_dias","lote_minimo","proveedor","ubicacion","se_repone"];
    downloadCSV("plantilla-inventario-vialseg.csv", headers, []);
  }
  function parseCSV(text) {
    const source = text.replace(/^\uFEFF/, "");
    let firstLine = "", quotedHead = false;
    for (let i = 0; i < source.length && source[i] !== "\n"; i++) {
      if (source[i] === '"' && source[i + 1] === '"') { i++; continue; }
      if (source[i] === '"') quotedHead = !quotedHead;
      if (!quotedHead) firstLine += source[i];
    }
    const delimiter = (firstLine.match(/;/g) || []).length > (firstLine.match(/,/g) || []).length ? ";" : ",";
    const rows = []; let row = []; let value = ""; let quoted = false;
    for (let i = 0; i < source.length; i++) {
      const c = source[i];
      if (quoted) {
        if (c === '"' && source[i + 1] === '"') { value += '"'; i++; }
        else if (c === '"') quoted = false;
        else value += c;
      } else if (c === '"') quoted = true;
      else if (c === delimiter) { row.push(value); value = ""; }
      else if (c === "\n") { row.push(value.replace(/\r$/, "")); rows.push(row); row = []; value = ""; }
      else value += c;
    }
    if (value.length || row.length) { row.push(value.replace(/\r$/, "")); rows.push(row); }
    return rows.filter((r) => r.some((x) => x.trim()));
  }
  function normalizeHeader(s) { return String(s || "").trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[\s-]+/g, "_"); }
  async function importCSV(file) {
    const rows = parseCSV(await file.text());
    if (rows.length < 2) throw new Error("El archivo no tiene filas de materiales.");
    const headers = rows[0].map(normalizeHeader);
    const index = (key, aliases) => {
      for (const candidate of [key].concat(aliases || [])) { const i = headers.indexOf(candidate); if (i >= 0) return i; }
      return -1;
    };
    const col = {
      sku:index("codigo",["sku","code"]), name:index("nombre",["material","name"]), category:index("categoria",["category"]),
      unit:index("unidad",["unit"]), stock:index("stock",["existencia"]), cost:index("costo_unitario",["costo","precio_unitario"]),
      use:index("consumo_mensual",["uso_mensual"]), safety:index("stock_seguridad",["seguridad"]),
      lead:index("plazo_dias",["lead_time"]), lot:index("lote_minimo",["lote_reposicion","lote"]), supplier:index("proveedor",["supplier"]),
      location:index("ubicacion",["deposito","location"]), replenish:index("se_repone",["reponer","replenish"])
    };
    if (col.sku < 0 || col.name < 0) throw new Error("La plantilla necesita al menos las columnas codigo y nombre.");
    let created = 0, updated = 0, changedStock = 0;
    const loading = showLoading("Importando materiales…");
    try {
      for (const row of rows.slice(1)) {
        const cell = (i, fallback) => i >= 0 && row[i] !== undefined && row[i].trim() !== "" ? row[i].trim() : fallback;
        const parseNum = (v) => {
          let clean = String(v || "0").trim().replace(/\s/g, "");
          if (clean.includes(",") && clean.includes(".")) clean = clean.lastIndexOf(",") > clean.lastIndexOf(".") ? clean.replace(/\./g, "").replace(",", ".") : clean.replace(/,/g, "");
          else clean = clean.replace(",", ".");
          return num(clean);
        };
        const sku = cell(col.sku, "");
        const name = cell(col.name, "");
        if (!sku || !name) continue;
        const existing = state.items.find((x) => x.sku.toLowerCase() === sku.toLowerCase());
        const item = {
          id: existing ? existing.id : "demo-i-" + Date.now() + "-" + Math.random().toString(36).slice(2,6),
          sku: sku, name: name, category: cell(col.category, existing ? existing.category : "General"),
          unit: cell(col.unit, existing ? existing.unit : "u"),
          stock: existing ? existing.stock : 0,
          unitCost: parseNum(cell(col.cost, existing ? existing.unitCost : 0)),
          avgCostUsd: existing ? num(existing.avgCostUsd) : 0,
          quoteRate: existing ? num(existing.quoteRate) : 0,
          monthlyUse: parseNum(cell(col.use, existing ? existing.monthlyUse : 0)),
          safetyStock: parseNum(cell(col.safety, existing ? existing.safetyStock : 0)),
          leadDays: parseNum(cell(col.lead, existing ? existing.leadDays : 0)),
          minimumLot: Math.max(0, parseNum(cell(col.lot, existing ? existing.minimumLot : 0))),
          supplier: cell(col.supplier, existing ? existing.supplier : ""),
          location: cell(col.location, existing ? existing.location : ""),
          replenish: /^(no|false|0)$/i.test(cell(col.replenish, existing ? (existing.replenish ? "si" : "no") : "si")) ? false : true,
          active: true, updatedAt: new Date().toISOString()
        };
        const savedItem = await persistItem(item, !existing, 0);
        if (!existing) created++; else updated++;
        if (col.stock >= 0 && row[col.stock] !== undefined && row[col.stock].trim() !== "") {
          const physical = parseNum(row[col.stock]);
          const current = itemById(savedItem.id);
          if (!current) throw new Error("Se guardó el material " + sku + ", pero no se pudo recuperar su stock para completar la importación.");
          if (Math.abs(num(current.stock) - physical) > 0.001) {
            await addMovement({ itemId: savedItem.id, type: "ajuste", quantity: physical, note: "Actualización de stock por importación CSV", reference: "CSV", actor: currentActor() || state.user.name, suppressRender: true });
            changedStock++;
          }
        }
      }
      await initializeUsdCostBaseline();
      render();
      toast("Importación finalizada: " + created + " nuevos, " + updated + " actualizados, " + changedStock + " ajustes de stock.");
    } finally { loading(); }
  }

  function setAuthError(message) {
    const error = $("#auth-error");
    error.textContent = message;
    show(error);
  }
  function showLogin() {
    const shell = $("#app-shell");
    const auth = $("#auth-screen");
    $("#login-form").hidden = !configured();
    const configNote = $("#auth-config-note");
    if (configNote) configNote.hidden = configured();
    if (!shell.hidden) {
      shell.classList.remove("app-enter");
      shell.classList.add("app-exit");
      window.setTimeout(() => {
        hide(shell);
        shell.classList.remove("app-exit");
        show(auth);
        auth.classList.add("auth-enter");
        window.setTimeout(() => auth.classList.remove("auth-enter"), 360);
      }, 180);
      return;
    }
    show(auth);
  }
  function enterApplication() {
    const auth = $("#auth-screen");
    const shell = $("#app-shell");
    const finish = () => {
      hide(auth);
      auth.classList.remove("auth-exit");
      show(shell);
      render();
      shell.classList.remove("app-enter");
      void shell.offsetWidth;
      shell.classList.add("app-enter");
      window.setTimeout(() => shell.classList.remove("app-enter"), 480);
    };
    if (auth.hidden) { finish(); return; }
    auth.classList.remove("auth-enter");
    auth.classList.add("auth-exit");
    window.setTimeout(finish, 220);
  }
  async function enterDemo() {
    state.mode = "demo";
    state.session = null;
    state.user = { name: "Administración demo", email: "demo@vialseg.local" };
    loadDemoData();
    enterApplication();
  }
  async function login(e) {
    e.preventDefault();
    if (!configured()) return;
    const button = $('button[type="submit"]', $("#login-form"));
    button.disabled = true; button.textContent = "Ingresando…";
    hide($("#auth-error"));
    try {
      const username = val("login-username").trim().toLowerCase();
      if (!/^[a-z0-9._-]{3,32}$/.test(username)) throw new Error("El usuario debe tener entre 3 y 32 caracteres: letras, números, punto, guion o guion bajo.");
      const data = await authRequest("token?grant_type=password", { email: authEmailForUsername(username), password: $("#login-password").value });
      $("#login-password").value = "";
      const session = { access_token: data.access_token, refresh_token: data.refresh_token, expires_at: Date.now() + (data.expires_in || 3600) * 1000, user: data.user };
      putSession(session, $("#remember-device").checked); state.mode = "remote"; state.user = data.user;
      await loadRemoteData();
      enterApplication();
    } catch (error) { setAuthError(error.message || "No se pudo ingresar."); }
    finally { button.disabled = false; button.innerHTML = 'Ingresar <span aria-hidden="true">↗</span>'; }
  }
  async function restore() {
    const hash = location.hash.replace("#", "");
    if (VIEW_NAMES[hash]) state.view = hash;
    if (!configured()) { showLogin(); return; }
    const session = getSession();
    if (!session) { showLogin(); return; }
    const loading = showLoading("Restaurando tu sesión…");
    try {
      state.session = session;
      if (session.expires_at < Date.now() + 30000 && !(await refreshAuth())) { showLogin(); return; }
      state.user = (state.session || session).user || session.user;
      const response = await fetch(CONFIG.supabaseUrl.replace(/\/$/, "") + "/auth/v1/user", { headers: { apikey: CONFIG.supabaseKey, Authorization: "Bearer " + (state.session || session).access_token } });
      if (!response.ok) throw new Error("La sesión expiró.");
      const user = await response.json();
      state.user = user;
      state.mode = "remote";
      await loadRemoteData();
      enterApplication();
    } catch (_) { putSession(null); showLogin(); }
    finally { loading(); }
  }

  async function logout() {
    if (state.mode === "remote" && state.session) {
      try { await fetch(CONFIG.supabaseUrl.replace(/\/$/, "") + "/auth/v1/logout", { method: "POST", headers: { apikey: CONFIG.supabaseKey, Authorization: "Bearer " + state.session.access_token } }); } catch (_) {}
    }
    putSession(null); state.mode = null; state.user = null; state.items = []; state.movements = [];
    showLogin();
  }

  function onSearchInput(e) {
    if (e.target.id === "price-history-item") renderCostItemSuggestions(e.target.value);
    if (e.target.id === "m-item-search") {
      const select = $("#m-item");
      const selected = itemById(select && select.value);
      const canonical = selected ? selected.sku + " · " + selected.name : "";
      if (String(e.target.value).trim().toLocaleLowerCase("es") !== canonical.toLocaleLowerCase("es")) select.value = "";
      updateMovementHelp();
      renderMovementItemSuggestions(e.target.value);
    }
    if (e.target.id === "item-search") {
      state.itemSearch = e.target.value;
      const region = $("#item-table-region");
      if (region) region.innerHTML = renderItemTable(filteredItems(), true);
      const count = $("#item-result-count"); if (count) count.textContent = filteredItems().length;
    }
    if (e.target.id === "item-code-search") {
      state.itemCodeSearch = e.target.value;
      const region = $("#item-table-region");
      if (region) region.innerHTML = renderItemTable(filteredItems(), true);
      const count = $("#item-result-count"); if (count) count.textContent = filteredItems().length;
    }
    if (e.target.id === "movement-search") {
      state.movementSearch = e.target.value;
      const region = $("#movement-table-region");
      if (region) region.innerHTML = renderMovementTable(filteredMovements(), true);
      const count = $("#movement-result-count"); if (count) count.textContent = filteredMovements().length;
    }
  }
  function csvInputClick() { $("#csv-file").value = ""; $("#csv-file").click(); }

  async function onClick(e) {
    const costChoice = e.target.closest("[data-cost-item-id]");
    if (costChoice) { selectCostItem(costChoice.dataset.costItemId); return; }
    const materialChoice = e.target.closest("[data-movement-item-id]");
    if (materialChoice) { selectMovementItem(materialChoice.dataset.movementItemId); return; }
    if (!e.target.closest(".material-picker")) hideMovementItemSuggestions();
    const nav = e.target.closest("[data-view]");
    if (nav) { setView(nav.dataset.view); return; }
    const actionEl = e.target.closest("[data-action]");
    if (actionEl) {
      const action = actionEl.dataset.action, id = actionEl.dataset.id, kind = actionEl.dataset.kind, quantity = actionEl.dataset.quantity;
      if (action === "new-item") showItemModal();
      else if (action === "edit-item") showItemModal(id);
      else if (action === "delete-item") await deleteItem(id);
      else if (action === "new-movement") showMovementModal(id, kind, quantity);
      else if (action === "edit-movement") showEditMovementModal(id);
      else if (action === "import-csv") csvInputClick();
      else if (action === "export-items") exportItems();
      else if (action === "export-movements") exportMovements();
      else if (action === "export-period-report") exportPeriodReport();
      else if (action === "apply-report-period") {
        const from = $("#report-from").value, to = $("#report-to").value;
        if (from && to && from > to) toast("La fecha inicial no puede ser posterior a la fecha final.", "error");
        else { state.reportFrom = from; state.reportTo = to; render(); }
      }
      else if (action === "export-replenishment") {
        const rows = candidates().map((i) => [i.sku,i.name,i.stock,i.unit,reorderPoint(i),minimumOrderQuantity(i),i.supplier,i.leadDays]);
        downloadCSV("vialseg-reposicion.csv", ["codigo","material","stock_actual","unidad","punto_pedido","cantidad_sugerida","proveedor","plazo_dias"], rows);
      } else if (action === "download-template") downloadTemplate();
      else if (action === "open-settings") showSettings();
      else if (action === "close-modal") closeModal();
      return;
    }
    if (e.target.closest("#logout-button")) { await logout(); return; }
    if (e.target.closest("#settings-button")) { showSettings(); return; }
    if (e.target.closest("#mobile-menu")) { $("#sidebar").classList.toggle("open"); return; }
    if (e.target.closest("#top-notifications")) { setView("replenishment"); return; }
    const closeTarget = e.target.closest("[data-close-modal]");
    if (closeTarget && (e.target === closeTarget || closeTarget.matches("button"))) { closeModal(); return; }
    if (e.target.id === "modal-root") closeModal();
  }

  document.addEventListener("click", (e) => { onClick(e).catch((error) => toast(error.message || "Ocurrió un error.", "error")); });
  document.addEventListener("input", onSearchInput);
  document.addEventListener("focusin", (e) => { if (e.target.id === "m-item-search") renderMovementItemSuggestions(e.target.value); if (e.target.id === "price-history-item") renderCostItemSuggestions(e.target.value); });
  document.addEventListener("keydown", (e) => {
    if (e.target.id === "price-history-item") {
      if (e.key === "Escape") { hideCostItemSuggestions(); return; }
      if (e.key === "Enter") {
        const first = $("#price-history-results [data-cost-item-id]");
        if (first && !$("#price-history-results").hidden) { e.preventDefault(); selectCostItem(first.dataset.costItemId); }
      }
      return;
    }
    if (e.target.id !== "m-item-search") return;
    if (e.key === "Escape") { hideMovementItemSuggestions(); return; }
    if (e.key === "Enter") {
      const first = $("#m-item-results [data-movement-item-id]");
      if (first && !$("#m-item-results").hidden) { e.preventDefault(); selectMovementItem(first.dataset.movementItemId); }
    }
  });
  document.addEventListener("change", (e) => {
    if (e.target.id === "item-location-filter") { state.itemLocation = e.target.value; render(); }
    if (e.target.id === "item-category-filter") { state.itemCategory = e.target.value; render(); }
    if (e.target.id === "item-class-filter") { state.itemClass = e.target.value; render(); }
    if (e.target.id === "item-status-filter") { state.itemStatus = e.target.value; render(); }
    if (e.target.id === "movement-type-filter") { state.movementType = e.target.value; render(); }
    if (e.target.id === "price-history-item") { const item = activeItems().find((candidate) => [candidate.sku, candidate.name, candidate.sku + " · " + candidate.name].some((option) => String(option || "").trim().toLocaleLowerCase("es") === e.target.value.trim().toLocaleLowerCase("es"))); if (item) selectCostItem(item.id); }
    if (e.target.id === "m-type" || e.target.id === "m-item") updateMovementHelp();
    if (e.target.id === "csv-file" && e.target.files && e.target.files[0]) importCSV(e.target.files[0]).catch((error) => toast(error.message || "No se pudo importar el CSV.", "error"));
  });
  document.addEventListener("submit", async (e) => {
    if (e.target.id === "login-form") { await login(e); return; }
    if (e.target.id === "item-form") { e.preventDefault(); await submitItemForm(e.target); return; }
    if (e.target.id === "movement-form") { e.preventDefault(); await submitMovementForm(); return; }
    if (e.target.id === "edit-movement-form") { e.preventDefault(); await submitEditMovementForm(e.target); return; }
  });
  window.addEventListener("hashchange", () => {
    const view = location.hash.replace("#", "");
    if (VIEW_NAMES[view] && view !== state.view) setView(view);
  });
  $("#demo-login").addEventListener("click", () => enterDemo());

  if (!configured()) {
    $("#login-form").hidden = true;
    $("#auth-config-note").hidden = false;
    $("#demo-login").hidden = false;
    $("#mode-chip").classList.add("demo");
  } else {
    $("#login-form").hidden = false;
    $("#auth-config-note").hidden = true;
    $("#demo-login").hidden = true;
  }
  restore();
})();
