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

## Résumé IA d'un cours (clé Google gratuite)

Le résumé utilise Gemini (`gemini-3.5-flash-lite`, gratuit).

Pour voir directement le tableau de bord de démonstration avec `Dina Jouini` et
`Mme Linda Wadaa`, sans écran de connexion Supabase :

```powershell
flutter run --dart-define=SUPABASE_URL= --dart-define=SUPABASE_PUBLISHABLE_KEY=
```

### Mode démo sans Supabase (disponible tout de suite)

Option A — injecter la clé au lancement, sans champ à remplir :

```powershell
flutter run --dart-define=GEMINI_API_KEY=votre_cle_ici
```

Pour un APK : `flutter build apk --dart-define=GEMINI_API_KEY=votre_cle_ici`.
La clé est alors compilée dans le binaire : ne distribuez pas cet APK à quelqu'un
qui ne doit pas voir la clé, et ne commitez jamais la vraie clé.

Option B — sans `dart-define` : au premier **Résumé IA du cours**, le dialogue
demande une clé créée dans https://aistudio.google.com/apikey. Dans ce cas, la
clé reste uniquement en mémoire pendant la session.

Dans les deux cas : ouvrez le menu `⋯` d'une séance, choisissez le PDF depuis
l'appareil (10 Mo maximum), puis **Générer le résumé**. Aucun appel ne passe par
Supabase dans ce mode. Si un modèle est saturé, l'application essaie
automatiquement `gemini-3.1-flash-lite`, `gemini-3.8-flash` puis
`gemini-3.6-flash`.

### Mode Supabase (à faire par la personne qui administre le projet)

La clé IA reste sur le serveur, jamais dans Flutter.

1. Depuis la racine du projet :

```powershell
supabase login
supabase link --project-ref hrcjrzjkdrikmhtovozo
supabase db push
supabase secrets set GEMINI_API_KEY=votre_cle_ici
supabase functions deploy summarize-course
```

Variante sans CLI : exécutez
`supabase/migrations/20261123000100_course_pdf_ai.sql` dans le SQL Editor, puis
ajoutez le secret `GEMINI_API_KEY` dans **Edge Functions → Secrets**.

2. Dans l'application avec un compte enseignant ou directeur, ouvrez le menu
   `⋯` d'une séance puis **Joindre un PDF** (10 Mo maximum). Ensuite, l'étudiante
   ouvre le même menu et choisit **Résumé IA du cours**.
3. Le résumé est mis en cache tant que le PDF ne change pas ; remplacer le PDF
   le invalide automatiquement.

Le modèle gratuit a des limites de requêtes : en cas de quota épuisé,
l'application affiche un message et le cache reste consultable.

## Vérification

```powershell
flutter analyze
flutter test
```
