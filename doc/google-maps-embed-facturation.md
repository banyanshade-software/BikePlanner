# Clé Google Maps Embed : éviter d'être facturé

Les libellés sont ceux de la console Google Cloud en français ; ils peuvent légèrement varier d'une version à l'autre.

**En bref** : l'API Maps Embed (celle que BikePlanner utilise pour Street View) est gratuite et sans limite
d'utilisation, d'après la page de tarification officielle de Google. Une utilisation normale ne peut donc rien coûter.

Le vrai risque, c'est le vol de la clé. Elle est intégrée à l'app (obscurcie, mais on peut la récupérer). Si elle
n'est pas restreinte, quelqu'un pourrait s'en servir pour appeler les API payantes de Google (Places, Directions…),
et la facture arriverait sur ton compte. Voici les réglages qui t'en protègent.

## 1. Un projet Google Cloud dédié

Crée un projet réservé à BikePlanner, par exemple `bikeplanner-embed`, et ne l'utilise que pour ça.
Dans **API et services → API et services activés**, active **uniquement l'API Maps Embed** (tu la trouves dans
**Bibliothèque**).

## 2. Restreindre la clé (l'étape la plus importante)

Dans **API et services → Identifiants**, clique sur ta clé :

- **Restrictions relatives aux API** : choisis **Restreindre la clé** et coche seulement **Maps Embed API**.
  Une clé volée ne pourra alors appeler aucune API payante.
- **Restrictions relatives aux applications** : choisis **Sites Web** et ajoute `https://bikeplanner.invalid/*`.
  L'app charge la page Street View avec cette adresse comme origine (`SupportClasses/StreetViewController.m`,
  `kEmbedPageBaseURL`), c'est donc le référent que Google voit, et cette restriction était prévue dans #49.
  Un référent peut se falsifier : c'est une deuxième barrière, pas la protection principale.
  Teste Street View dans l'app après ce réglage. Si le panorama ne s'affiche plus, retire cette restriction et garde
  seulement celle sur les API.

## 3. Plafonds et alertes

- **Facturation → Budgets et alertes** : crée un budget de 1 € avec des alertes par e-mail à 50 % et 100 %.
  Ça ne bloque rien, ça te prévient seulement, mais tu sauras tout de suite s'il y a un problème.
- **API et services → Maps Embed API → Quotas et limites système** : tu peux baisser le quota quotidien
  (quelques centaines de requêtes par jour suffisent largement pour un usage personnel). Une fois le quota atteint,
  Google arrête de répondre au lieu de continuer à compter.
- Pour une vraie coupure automatique, Google documente une façon de désactiver la facturation quand le budget est
  dépassé (une alerte Pub/Sub plus une Cloud Function). C'est sûrement excessif ici, une fois la clé restreinte à
  l'API Maps Embed.

## 4. Vérifier

- Les premiers temps, regarde une fois par mois **Facturation → Rapports**. Ça doit rester à 0 €.
- Ne publie pas le DMG : il contient les deux clés (déjà noté dans `CLAUDE.md`).

Google te demandera peut-être un compte de facturation (une carte bancaire) pour créer la clé. Tant que la clé est
restreinte à l'API Maps Embed, rien de ce qui passe par elle n'est facturable.

## Sources

- [Maps Embed API Usage and Billing (Google)](https://developers.google.com/maps/documentation/embed/usage-and-billing)
- [Google Maps API Pricing 2026 (superdupr)](https://superdupr.com/blog/google-maps-api-pricing)
