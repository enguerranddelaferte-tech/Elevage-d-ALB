# Élevage d'ALB — appli gérant + espace cavaliers

Une seule écurie, deux espaces dans la même appli :
- **Gérant** : chevaux, soins, silo à grain, planning des cours, tâches du jour, cavaliers et carnets de cours, registre d'élevage, annonces, messages.
- **Cavaliers** (propriétaires, demi-pensionnaires, cavaliers) : réservation des cours, chevaux de l'écurie, suivi de leur cheval, signalement d'un problème, tâches du jour visibles, annonces, messagerie avec le gérant.

L'appli ne fait pas de facturation ni de comptabilité.

L'hébergement est gratuit : **GitHub Pages** pour l'appli, **Supabase** pour la base de données partagée.

## Contenu du dossier

- `index.html` : l'application
- `config.js` : l'adresse de votre base Supabase (à remplir, étape 2)
- `supabase-installation.sql` : le script qui crée la base (étape 1)
- `supabase/functions/` : les petits services en ligne (météo, notifications et e-mails)
- `manifest.webmanifest`, `sw.js`, `icons/` : installation sur téléphone et fonctionnement hors ligne

Tant que `config.js` est vide, l'appli fonctionne en **mode démo** : données d'exemple gardées dans le navigateur, et un sélecteur « Voir l'appli comme… » (Réglages) pour tester l'espace d'un cavalier.

## 1. Créer la base Supabase (une fois, 10 minutes)

1. Créez un compte sur https://supabase.com puis **New project**. Région : **Europe (Paris ou Frankfurt)**. Notez le mot de passe de la base.
2. **Authentication › Sign In / Providers › Email** : désactivez **Confirm email**, puis enregistrez.
   (La sécurité repose sur le code d'activation que vous donnez à chaque cavalier. Sans cette option, Supabase devrait envoyer un e-mail à chaque inscription, et son service d'e-mails gratuit est très limité.)
3. **SQL Editor › New query** : collez tout le contenu de `supabase-installation.sql`, puis **Run**.
   Le résultat affiche votre **CODE D'ACTIVATION GÉRANT** : notez-le précieusement.
4. **Project Settings › API** : copiez **Project URL** et la clé **anon public**.

## 2. Relier l'appli à la base

Ouvrez `config.js` et collez les deux valeurs entre les apostrophes :

```js
window.ECURIE_CONFIG = {
  supabaseUrl: 'https://xxxxxxxx.supabase.co',
  supabaseKey: 'eyJhbGciOi...'
};
```

La clé « anon » est prévue pour être publique : ce sont les règles d'accès de la base qui protègent les données (un cavalier voit les chevaux de l'écurie, les cours, les annonces, les tâches que vous rendez visibles, et seulement ses propres messages et sa fiche).

## 3. Mettre l'appli en ligne avec GitHub Pages

1. Sur https://github.com : **+ › New repository**, nom `ecurie`, **Public**, **Create repository**.
2. **uploading an existing file** : glissez **tout le contenu** du dossier (`index.html`, `config.js`, `sw.js`, `manifest.webmanifest`, le dossier `icons`…). **Commit changes**.
   `index.html` doit être à la racine du dépôt.
3. **Settings › Pages** : Source **Deploy from a branch**, Branch **main** et **/(root)**, **Save**.
4. Après une à deux minutes, l'appli est à l'adresse `https://VOTRE-PSEUDO.github.io/ecurie/`.

## 4. Premier lancement du gérant

1. Ouvrez l'adresse, touchez **Première connexion : créer mon compte**.
2. Saisissez votre e-mail, un mot de passe et le **code d'activation gérant** (étape 1.3).
3. Renseignez Réglages › **Mon écurie** (adresse et n° de détenteur pour le registre), vos **pensions** et le délai d'annulation des cours.
4. Pour reprendre les données d'une version précédente : dans l'ancienne appli, Réglages › Télécharger la sauvegarde, puis ici Réglages › Restaurer.

## 5. Inviter les cavaliers

1. Onglet **Cavaliers** › **+ Cavalier** › Enregistrer : la fiche se rouvre avec son **code d'activation** prêt.
2. **Envoyer l'invitation (SMS, WhatsApp…)** : le message contient le lien de l'appli et le code. Pour une fiche existante : **Créer l'invitation**.
3. Le cavalier ouvre le lien, crée son compte avec ce code ; sa fiche affiche ensuite « Compte activé ». Chaque code ne sert qu'une fois.

## 6. Installer sur le téléphone

- **Android (Chrome)** : bandeau « Installer », ou menu ⋮ › Installer l'application.
- **iPhone (Safari)** : Partager › **Sur l'écran d'accueil**.

## Chevaux

- **Fiche cheval** : race, sexe, date de naissance (l'âge se calcule), n° SIRE/UELN, n° de puce, box ou pré, arrivée et provenance, propriétaire, « disponible pour les cours ».
- **Statut** : votre cheval (propriétaire « L'écurie ») n'a pas de pension. Le cheval d'un propriétaire est soit **en pension** (on choisit la pension), soit **prêté à l'écurie** (pas de pension) ; dans les deux cas, la case « disponible pour les cours » en fait un cheval de club.
- **Grain** : chaque cheval reçoit un ou plusieurs grains du silo, avec la quantité en litres le matin, le midi et le soir. Le fourrage et les compléments restent en texte libre.
- **Silo à grain** (onglet Silo du menu) : la liste de vos grains, avec le stock en litres. Le silo calcule la consommation par jour et le nombre de jours de stock ; « À commander » s'affiche sous 7 jours.
- **Rations** (Chevaux › Rations) : tableau grain, fourrage et consignes par box, à imprimer ou copier.
- **Départ** : fiche du cheval › « Le cheval quitte l'écurie » : date, motif (vente, retour chez le propriétaire, changement d'écurie, retraite, prêt, décès, autre) et destination. Le cheval sort des listes, apparaît dans « Chevaux partis » et reste dans le registre. « Le cheval est revenu » annule le départ.
- **Soins** : prévus ou faits, type de vermifuge (ivermectine, moxidectine, praziquantel, pyrantel, fenbendazole…), soin groupé pour plusieurs chevaux avec rappel automatique. Le propriétaire peut noter lui-même un soin.

## Registre d'élevage

Onglet **Registre** : tous les équidés passés par l'écurie (identification, propriétaire, date d'entrée et provenance, date de sortie, motif et destination) et tous les soins faits. Il se remplit tout seul avec les fiches des chevaux.
- **Imprimer ou enregistrer en PDF** : document A4 paysage avec l'en-tête de l'écurie (nom, adresse, n° de détenteur).
- **Exporter (Excel)** : deux fichiers CSV, équidés et soins.

## Pensions et cours

- **Pensions personnalisées** (Réglages › Pensions) : créez vos formules (« Pension complète + 2 cours »…) avec le nombre de cours autorisés par semaine : non limité, aucun, ou de 1 à 7.
- Le nombre de cours s'applique au propriétaire du cheval (chevaux en pension seulement). Une **demi-pension** (fiche du cheval › Cavaliers › Confier) peut aussi compter des cours par semaine : ils s'ajoutent à ceux du cavalier. Le cavalier voit « Pension : 2 cours par semaine · 1 réservé ». Au-delà, il lui faut un carnet de cours pour réserver.
- **Carnets de cours** (sans prix) : fiche du cavalier › Carnets de cours › 5, 10 ou 20 cours. Les cours sont décomptés automatiquement, après ceux compris dans la pension. Vue Cavaliers › « Carnets de cours » : où en est chaque cavalier, correction +1 / −1.
- **Inscrits visibles** : chaque cavalier voit qui est inscrit à chaque cours (prénom et initiale du nom, avec ✓ présent ou ✗ absent) ; seuls les cours particuliers des autres restent masqués.
- **Planning** : semaine ou mois, cours répétés chaque semaine, concours, monte libre réservée par le cavalier, choix du cheval de chaque cavalier.
- **Présence** : le cavalier indique « présent » ou « absent ». Avant le délai d'annulation, « absent » propose de libérer la place.

## Cavaliers

- **Tous les chevaux** : onglet Chevaux de l'espace cavalier, avec la fiche de chaque cheval (box, consignes, ration) et le bouton **Signaler un problème** (blessure, ne mange pas, comportement, matériel, box ou clôture…).
- **Signalements** : vous êtes prévenu tout de suite ; ils s'affichent en haut de l'accueil et dans les alertes. « Marquer réglé » prévient le cavalier, « Répondre » ouvre la conversation.
- **Tâches du jour** : chaque tâche est **visible** ou **privée** (vous seul). Les tâches visibles apparaissent chez tous les cavaliers et parents, qui peuvent **les cocher** quand ils les ont faites ; tout le monde voit « Fait par Inès R. ». Touchez « Visible » ou « Privée » pour changer.
- Fiche : **prénom et nom** séparés, rôles (propriétaire, cavalier, demi-pensionnaire), date de naissance, chevaux confiés (demi-pension, location, prêt).
- **Cavalier mineur et compte parent** : cocher « Cavalier mineur » et remplir le responsable légal (prénom, nom, lien, téléphone, e-mail). Dans « Espace cavalier », **Créer l'invitation du parent** donne un second code : le parent crée son propre compte, relié à la même fiche. Le parent réserve et annule les cours, demande les carnets, modifie les coordonnées et écrit à l'écurie (ses messages sont marqués « Parent »). L'enfant voit ses cours et les chevaux, confirme sa présence, écrit et signale un problème, mais ne réserve pas seul, sauf si la case « Le cavalier peut réserver et annuler ses cours seul » est cochée. Les deux reçoivent les notifications.

## Statistiques

Onglet **Stats** (gérant) : par mois, trimestre, année ou 12 mois glissants, avec les flèches pour changer de période.
- Cours donnés, participations, cavaliers venus, remplissage des cours collectifs, absences signalées, cours annulés.
- **Cours par cavalier** : nombre de cours (collectifs, particuliers), moyenne par semaine comparée aux cours compris dans sa pension, absences, cours restants sur son carnet. Export Excel.
- Graphiques : cours par mois, jours et créneaux les plus fréquentés, chevaux de club les plus montés, soins faits (vermifuges par molécule), chevaux par pension, arrivées et départs, consommation de grain estimée, problèmes signalés.
- Seuls les cours passés et non annulés comptent ; un cavalier signalé absent n'est pas compté. Imprimable en PDF.

## Alertes

La case « alertes » de l'accueil s'ouvre d'un toucher : chaque alerte dit ce qu'il faut faire. Soin à faire : « C'est fait », « Reporter d'une semaine » ou « Fiche du cheval ». Assurance qui expire : « Fiche du cavalier ». Problème signalé : « Marquer réglé » ou « Répondre ».

## Notifications

- **Cloche** en haut de l'écran : toutes les notifications (cours annulé ou modifié, inscription, message, annonce, signalement). Pastille rouge = non lues.
- **Sur le téléphone, même appli fermée** : chaque personne touche « Activer les notifications » (bandeau d'accueil ou Réglages). Sur iPhone, il faut d'abord installer l'appli sur l'écran d'accueil (iOS 16.4 ou plus récent).
- **Annuler des cours** : Planning › « Annuler les cours de ce jour… », motif en un clic (Piste gelée…). Les cavaliers inscrits sont prévenus.
- **Météo du matin** : chaque jour à 7 h, une notification avec le temps du jour et les cours. Désactivable par téléphone dans Réglages › Notifications.

## Écrans

L'appli s'adapte au téléphone, à la tablette (contenu sur deux colonnes) et à l'ordinateur (menu à gauche, rangé en Au quotidien, Suivi, Infos). Sur téléphone, la barre du bas garde Accueil, Chevaux, Cours, Cavaliers ; « Plus » ouvre Silo, Stats, Registre, Météo, Messages et Réglages. Le bouton + en haut ajoute selon l'écran (cheval, cours, cavalier, grain). La fiche d'un cheval est rangée en onglets : Fiche, Ration, Soins, Cavaliers.

## Météo

Sur l'écran Aujourd'hui (gérant) et l'Accueil (cavaliers) : la météo du jour, les 4 prochains jours et des conseils pour les chevaux. Le gérant choisit la commune avec le bouton « Changer ».
Sources ouvertes : prévisions MET Norway (api.met.no, CC BY 4.0) et recherche de commune geo.api.gouv.fr (licence ouverte Etalab).

## Bon à savoir

- **Offre gratuite Supabase** : 500 Mo de base, largement suffisant pour une écurie. Un projet gratuit est mis en pause après 7 jours sans activité ; relancez-le d'un clic dans le tableau de bord Supabase, les données sont conservées.
- **Mot de passe oublié** : le lien de réinitialisation est envoyé par e-mail par Supabase.
- **RGPD** : les coordonnées des cavaliers sont stockées en ligne. Informez-les (finalité : gestion de la pension et des cours ; droit d'accès et de rectification auprès du gérant).
- **Sauvegarde** : Réglages › Télécharger la sauvegarde, de temps en temps.

## Mettre à jour l'appli

Sur GitHub : **Add file › Upload files**, glissez les nouveaux fichiers (sauf `config.js`, déjà rempli), **Commit changes**. L'appli se met à jour à la prochaine ouverture. Les données, elles, sont dans Supabase et ne sont pas touchées.
