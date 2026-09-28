'use strict';
'require view';
'require rpc';
'require fs';
'require ui';
'require poll';

var callInitAction = rpc.declare({
	object: 'luci', method: 'setInitAction',
	params: [ 'name', 'action' ], expect: { result: false }
});

function status() {
	return fs.exec('/usr/libexec/amneziawg3-status').then(function(r) {
		try { return JSON.parse(r.stdout); } catch (e) { return null; }
	}).catch(function() { return null; });
}

function mb(b) { return (b / 1048576).toFixed(1) + ' MB'; }

function badge(ok, text) {
	return E('span', {
		'style': 'display:inline-block;padding:.35em .9em;border-radius:1em;font-weight:bold;color:#fff;background:' + (ok ? '#2e7d32' : '#9e9e9e')
	}, text);
}

function render_status(s) {
	if (!s) return E('em', {}, _('Status unavailable'));
	var connected = s.up && s.handshake_age >= 0 && s.handshake_age <= 180;
	var head;
	if (!s.up) head = badge(false, _('OFF — whole network goes direct'));
	else if (connected) head = badge(true, _('ON — connected'));
	else head = E('span', { 'style': 'display:inline-block;padding:.35em .9em;border-radius:1em;font-weight:bold;color:#fff;background:#e65100' }, _('ON — no handshake (server or internet down)'));

	var rows = [
		[ _('Internet cable (WAN)'), s.wan_link ? _('connected') : _('NOT connected') ]
	];
	if (s.up) rows = rows.concat([
		[ _('Last handshake'), s.handshake_age >= 0 ? s.handshake_age + ' s ago' : _('never') ],
		[ _('Tunnel ping'), s.rtt ? s.rtt + ' ms' : _('no reply') ],
		[ _('Traffic'), _('down') + ' ' + mb(s.rx) + ' / ' + _('up') + ' ' + mb(s.tx) ],
		[ _('Server'), s.endpoint || '-' ],
		[ _('Local port'), s.listen_port ],
		[ _('LAN → VPN rule'), s.rule ? _('active') : _('missing') ],
		[ _('Direct (bypass) routes'), String(s.bypass) ]
	]);
	rows.push([ _('Start at boot'), s.boot ? _('yes') : _('no') ]);

	return E('div', {}, [
		E('p', { 'style': 'font-size:1.2em' }, head),
		E('table', { 'class': 'table' }, rows.map(function(r) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'style': 'width:35%' }, r[0]),
				E('td', { 'class': 'td left' }, r[1])
			]);
		}))
	]);
}

return view.extend({
	load: function() { return status(); },

	action: function(act, ev) {
		var btn = ev.currentTarget;
		btn.disabled = true;
		return callInitAction('amneziawg3', act).then(function() {
			return new Promise(function(res) { setTimeout(res, act == 'stop' ? 1000 : 4000); });
		}).then(status).then(function(s) {
			var box = document.getElementById('awg-status');
			box.replaceChildren(render_status(s));
			ui.addNotification(null, E('p', {}, {
				'restart': _('VPN turned on.'), 'stop': _('VPN turned off — the whole network now goes direct.'),
				'enable': _('VPN will start at boot.'), 'disable': _('VPN will NOT start at boot.')
			}[act]), 'info');
		}).finally(function() { btn.disabled = false; });
	},

	render: function(s) {
		poll.add(function() {
			return status().then(function(s) {
				var box = document.getElementById('awg-status');
				if (box) box.replaceChildren(render_status(s));
			});
		}, 10);

		var btn = function(label, cls, act) {
			return E('button', { 'class': 'cbi-button ' + cls, 'style': 'margin-right:.6em;min-width:9em',
				'click': ui.createHandlerFn(this, 'action', act) }, label);
		}.bind(this);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('AmneziaWG VPN')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Whole-network AmneziaWG 3.1 tunnel. Destinations in the bypass list always go direct. Turning it off sends every device straight to the internet.')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'id': 'awg-status' }, render_status(s)),
				E('div', { 'style': 'margin-top:1.2em' }, [
					btn(_('Turn ON'), 'cbi-button-apply', 'restart'),
					btn(_('Turn OFF'), 'cbi-button-reset', 'stop'),
					btn(_('Start at boot'), 'cbi-button-neutral', 'enable'),
					btn(_("Don't start at boot"), 'cbi-button-neutral', 'disable')
				])
			])
		]);
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
