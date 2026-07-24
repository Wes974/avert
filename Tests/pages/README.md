# Pages de test manuelles

Servies par `scripts/nocache_server.py` (Safari **cache** les pages de test : ne
jamais servir sans `no-store`, et ajouter `?cb=<random>` à la main).

```bash
uv run --no-project python scripts/nocache_server.py 8787
```

Puis, sur l'iPhone (même LAN ou via Tailscale — l'IP Tailscale du Mac marche
hors du même Wi-Fi) :

| Scénario | URL |
|---|---|
| Point de capture dans une iframe tierce | `http://<mac>:8787/iframe-capture/top.html?frame=http://<autre-hôte-du-mac>:8787/iframe-capture/frame.html&cb=1` |

Les deux hôtes doivent différer (IP LAN vs IP Tailscale, ou `localhost` vs
`127.0.0.1` dans le simulateur), sinon la frame est same-site et **exemptée** par
`frameSignals` — ce qui est le comportement voulu, pas un bug.

Oracle de vérification : le log natif (`subsystem == "com.ouweis.avert"`).

```bash
# simulateur
xcrun simctl spawn <UDID> log stream --style compact --predicate 'subsystem == "com.ouweis.avert"'
# iPhone physique (libimobiledevice)
idevicesyslog -u <UDID> | grep -i avert
```

Attendu sur ce scénario : le moteur est appelé **alors que la page du haut n'a
aucun champ sensible** (score 25, verdict `silent` — un champ de paiement
embarqué légitime doit rester silencieux). C'est l'appel lui-même qui prouve que
le relais sous-frame → frame du haut fonctionne.
