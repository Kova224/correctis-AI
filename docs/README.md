# Hébergement de la politique de confidentialité via GitHub Pages

Google Play **exige** une URL publique pour la politique de confidentialité.
On la sert gratuitement via GitHub Pages, depuis ton propre repo.

## Activer GitHub Pages (3 min)

1. Va sur ton repo GitHub : https://github.com/Kova224/correctis-AI
2. Clique **Settings** (en haut)
3. Menu de gauche → **Pages**
4. Section **Source** :
   - Branch : **`main`**
   - Folder : **`/docs`**
5. Clique **Save**

Attends 1-2 minutes que GitHub publie. L'URL de ta politique sera :

```
https://kova224.github.io/correctis-AI/privacy.html
```

(remplace `kova224` par ton nom GitHub si différent)

## Vérifier que ça marche

Ouvre l'URL dans ton navigateur. Tu dois voir la page de politique de
confidentialité bien formatée. Si tu vois une 404, attends encore 1 minute
(GitHub Pages met parfois 5 min à publier la première fois).

## C'est cette URL que tu mettras

- Dans le formulaire Play Console (champ **Privacy policy**)
- Dans la description longue de l'app (ligne `https://VOTRE_USERNAME...`)
- Dans le code de l'app si tu veux y faire référence

## Pour mettre à jour la politique plus tard

Modifie `docs/privacy.html` → commit → push → GitHub Pages republie
automatiquement en ~1 minute. L'URL ne change pas.
