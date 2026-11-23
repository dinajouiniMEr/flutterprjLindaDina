# Présence

Application Flutter responsive de suivi des absences et des réclamations, avec
un thème blanc et mauve. L’interface propose des espaces étudiant, enseignant
et direction. Sans configuration Supabase, elle démarre en mode démo avec des
actions interactives et des données locales temporaires.

## Démarrer en mode démo

```powershell
flutter pub get
flutter run -d chrome
```

Le menu de profil en bas de la navigation permet de passer d’un rôle de démo à
l’autre.

## Connecter Supabase

1. Dans le SQL Editor du projet Supabase, exécutez
   `supabase/migrations/20261123000000_initial_schema.sql`.
2. Dans **Authentication → Users**, créez au moins deux utilisateurs de test :
   un étudiant et un enseignant. Le déclencheur SQL crée leur profil
   automatiquement.
3. Ouvrez `supabase/seed.sql` dans l’éditeur SQL. Remplacez les deux e-mails
   d’exemple par ceux des utilisateurs créés. Vous pouvez aussi modifier
   `demo_class` (la classe), puis exécutez le script dans le SQL Editor. Il
   attribue les rôles, crée l’emploi du temps de la semaine, des déclarations
   d’assiduité et des réclamations de démonstration. Un compte directeur est
   facultatif : ajoutez son e-mail à `director_email` pour le configurer aussi.
4. L’URL du projet et sa clé publiable sont configurées par défaut dans
   `lib/main.dart`. Vous pouvez démarrer l’application directement :

```powershell
flutter run -d chrome
```

L’application demande alors une connexion e-mail/mot de passe. Les profils et
les autorisations sont contrôlés par Supabase Auth et les politiques RLS de la
migration. Les déclarations, décisions et modifications de réclamations sont
enregistrées dans la base et historisées dans `audit_logs`.

La clé configurée est une clé publique (`sb_publishable_`) destinée à
l’application cliente. N’utilisez jamais une clé `service_role` ou
`sb_secret_` dans Flutter.

Pour vérifier que la base contient les données de démo, les dernières requêtes
de `supabase/seed.sql` affichent les profils, les séances, les présences et les
réclamations. Connectez-vous ensuite avec les comptes Auth correspondants.

## Vérification

```powershell
flutter analyze
flutter test
```
