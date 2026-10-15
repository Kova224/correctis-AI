# Passer le proxy CinetPay en HTTPS

Aujourd'hui, `CINETPAY_PROXY_URL` vaut `http://<IP du VPS>`. La clé et le mot de passe API CinetPay circulent donc en clair. Depuis la version 1.0.64, les Edge Functions refusent ce proxy en production (`CINETPAY_ENV=PROD`).

## Étapes (≈ 20 min)

1. **DNS.** Créer un enregistrement `A` : `cinetpay-proxy.correctis.app` → IP du VPS (n'importe quel domaine que vous contrôlez convient).
2. **Pare-feu du VPS.** Ouvrir les ports 80 et 443 en entrée (Let's Encrypt en a besoin).
3. **Secrets Caddy.** Créer `/etc/caddy/correctis.env` (chmod 600) :
   ```
   PROXY_DOMAIN=cinetpay-proxy.correctis.app
   PROXY_SECRET=<valeur actuelle de CINETPAY_PROXY_SECRET>
   ```
   et ajouter `EnvironmentFile=/etc/caddy/correctis.env` au service systemd de Caddy (`systemctl edit caddy`).
4. **Caddyfile.** Remplacer `/etc/caddy/Caddyfile` par le fichier de ce dossier, puis `systemctl restart caddy`.
5. **Test** depuis n'importe quel PC :
   ```
   curl -i https://cinetpay-proxy.correctis.app/v1/oauth/login          # → 403 (pas de secret)
   ```
6. **Supabase → Edge Functions → Secrets.** `CINETPAY_PROXY_URL` = `https://cinetpay-proxy.correctis.app` (sans `/` final).
7. **Changer le mot de passe API CinetPay**, car l'ancien a circulé en clair : console CinetPay → Ressources → API & sécurité → « Définir un mot de passe API ». Mettre la nouvelle valeur dans `CINETPAY_SECRET_KEY`.
8. Faire un paiement test (Sandbox) et vérifier dans les logs de `cinetpay-init-payment` : `baseUrlUsed: PROXY`.
