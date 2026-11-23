import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/attendance_repository.dart';
import 'data/gemini_summary_service.dart';

const _ink = Color(0xFF28233A);
const _muted = Color(0xFF8A8798);
const _purple = Color(0xFF7654D6);
const _purpleDark = Color(0xFF5F3DBE);
const _lavender = Color(0xFFF0EBFF);
const _canvas = Color(0xFFF8F7FB);
const _line = Color(0xFFECEAF1);
const _green = Color(0xFF2E9D72);
const _orange = Color(0xFFE19A42);
const _red = Color(0xFFD85E6A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hrcjrzjkdrikmhtovozo.supabase.co',
  );
  const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_aLHA-ssDMkjj-B-JRj1r_A_jYa-E_aM',
  );
  if (url.isNotEmpty && publishableKey.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }
  runApp(const AttendanceApp());
}

enum AppRole { student, teacher, director }

extension AppRoleLabels on AppRole {
  String get label => switch (this) {
    AppRole.student => 'Étudiant',
    AppRole.teacher => 'Enseignant',
    AppRole.director => 'Directeur',
  };

  String get firstName => switch (this) {
    AppRole.student => 'Dina Jouini',
    AppRole.teacher => 'Mme Linda Wadaa',
    AppRole.director => 'Mme Nadia',
  };

  IconData get icon => switch (this) {
    AppRole.student => Icons.school_outlined,
    AppRole.teacher => Icons.cast_for_education_outlined,
    AppRole.director => Icons.admin_panel_settings_outlined,
  };

  static AppRole fromDatabase(Object? value) => switch (value) {
    'teacher' => AppRole.teacher,
    'director' => AppRole.director,
    _ => AppRole.student,
  };
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.isInitialized
        ? Supabase.instance.client
        : null;
    return MaterialApp(
      title: 'Présence',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _purple,
          primary: _purple,
          surface: Colors.white,
          error: _red,
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: _ink,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          titleLarge: TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(color: _ink, fontSize: 14),
          bodySmall: TextStyle(color: _muted, fontSize: 12),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _canvas,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
      home: client == null ? const DashboardGate() : AuthGate(client: client),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({required this.client, super.key});

  final SupabaseClient client;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = client.auth.currentUser;
        if (user == null) return LoginScreen(client: client);
        return FutureBuilder<Map<String, dynamic>>(
          future: client.from('profiles').select().eq('id', user.id).single(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_outlined,
                          color: _red,
                          size: 36,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Impossible de charger votre profil.',
                          style: TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          profileSnapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => client.auth.signOut(),
                          child: const Text('Se déconnecter'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (!profileSnapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator(color: _purple)),
              );
            }
            final profile = profileSnapshot.data!;
            return DashboardGate(
              client: client,
              role: AppRoleLabels.fromDatabase(profile['role']),
            );
          },
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.client, super.key});

  final SupabaseClient client;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'Connexion impossible : $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: _line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandMark(),
                      const SizedBox(height: 30),
                      Text(
                        'Bon retour 👋',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Connectez-vous à votre espace scolaire.',
                        style: TextStyle(color: _muted),
                      ),
                      const SizedBox(height: 26),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Adresse e-mail',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: (value) =>
                            value == null || !value.contains('@')
                            ? 'Saisissez une adresse e-mail valide.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Saisissez votre mot de passe.'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(_error!, style: const TextStyle(color: _red)),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _loading ? null : _signIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: _purple,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Se connecter'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardGate extends StatelessWidget {
  const DashboardGate({
    this.client,
    this.role = AppRole.student,
    super.key,
  });

  final SupabaseClient? client;
  final AppRole role;

  @override
  Widget build(BuildContext context) => AttendanceDashboard(
    repository: client == null ? null : AttendanceRepository(client!),
    initialRole: role,
    userName: role.firstName,
  );
}

enum _Page { overview, schedule, attendance, claims }

extension on _Page {
  String get title => switch (this) {
    _Page.overview => 'Vue d’ensemble',
    _Page.schedule => 'Emploi du temps',
    _Page.attendance => 'Mes présences',
    _Page.claims => 'Réclamations',
  };

  IconData get icon => switch (this) {
    _Page.overview => Icons.grid_view_rounded,
    _Page.schedule => Icons.calendar_month_outlined,
    _Page.attendance => Icons.fact_check_outlined,
    _Page.claims => Icons.chat_bubble_outline_rounded,
  };

  String labelFor(AppRole role) => this == _Page.attendance
      ? switch (role) {
          AppRole.student => 'Mes présences',
          AppRole.teacher => 'Validations',
          AppRole.director => 'Assiduité',
        }
      : title;
}

class AttendanceDashboard extends StatefulWidget {
  const AttendanceDashboard({
    required this.repository,
    required this.initialRole,
    required this.userName,
    super.key,
  });

  final AttendanceRepository? repository;
  final AppRole initialRole;
  final String userName;

  @override
  State<AttendanceDashboard> createState() => _AttendanceDashboardState();
}

class _AttendanceDashboardState extends State<AttendanceDashboard> {
  late AppRole _role = widget.initialRole;
  _Page _page = _Page.overview;
  bool _searchVisible = false;
  final _searchController = TextEditingController();
  String _localApiKey = kGeminiApiKeyFromBuild;
  late Future<List<SchoolSession>> _sessionsFuture;
  late Future<List<AttendanceClaim>> _claimsFuture;
  late Future<List<AttendanceEntry>> _attendanceFuture;
  List<SchoolSession> _demoSessions = List.of(demoSessions);
  List<AttendanceClaim> _demoClaims = List.of(demoClaims);
  List<AttendanceEntry> _demoAttendance = List.of(demoAttendanceEntries);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim().toLowerCase();

  void _onSearchChanged() => setState(() {});

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  void _reload() {
    _sessionsFuture =
        widget.repository?.loadSessions() ?? Future.value(_demoSessions);
    _claimsFuture =
        widget.repository?.loadClaims() ?? Future.value(_demoClaims);
    _attendanceFuture =
        widget.repository?.loadAttendanceRecords() ??
        Future.value(_demoAttendance);
  }

  void _navigate(_Page page) => setState(() => _page = page);

  String get _displayName =>
      widget.repository == null ? _role.firstName : widget.userName;

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? _red : _ink,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _declareAttendance(SchoolSession session, bool present) async {
    try {
      if (widget.repository != null) {
        await widget.repository!.declareAttendance(
          session.id,
          present: present,
        );
      }
      setState(() {
        _demoSessions = _demoSessions
            .map(
              (item) => item.id == session.id
                  ? item.copyWith(
                      status: present
                          ? AttendanceStatus.declared
                          : AttendanceStatus.declaredAbsent,
                    )
                  : item,
            )
            .toList();
        _reload();
      });
      _showMessage(
        present
            ? 'Votre présence a été déclarée à l’enseignant.'
            : 'Votre absence a été déclarée à l’enseignant.',
      );
    } catch (error) {
      _showMessage('La déclaration a échoué : $error', isError: true);
    }
  }

  Future<void> _submitClaim(
    SchoolSession session,
    String reason,
    String details,
  ) async {
    try {
      if (widget.repository != null) {
        await widget.repository!.submitClaim(
          session.id,
          reason: reason,
          details: details,
        );
      } else {
        _demoClaims = [
          AttendanceClaim(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            sessionId: session.id,
            courseName: session.courseName,
            reason: reason,
            details: details,
            status: 'pending',
            createdAt: DateTime.now(),
          ),
          ..._demoClaims,
        ];
      }
      setState(_reload);
      _showMessage('Votre réclamation a été transmise.');
    } catch (error) {
      _showMessage(
        'L’envoi de la réclamation a échoué : $error',
        isError: true,
      );
    }
  }

  Future<void> _resolveClaim(AttendanceClaim claim, String status) async {
    try {
      if (widget.repository != null) {
        await widget.repository!.resolveClaim(claim.id, status);
      } else {
        _demoClaims = _demoClaims
            .map(
              (item) =>
                  item.id == claim.id ? item.copyWith(status: status) : item,
            )
            .toList();
      }
      setState(_reload);
      _showMessage(
        status == 'approved'
            ? 'La réclamation a été acceptée.'
            : 'La réclamation a été refusée.',
      );
    } catch (error) {
      _showMessage(
        'La décision n’a pas pu être enregistrée : $error',
        isError: true,
      );
    }
  }

  Future<void> _validateAttendance(AttendanceEntry entry, String status) async {
    try {
      if (widget.repository != null) {
        await widget.repository!.validateAttendance(entry.id, status: status);
      } else {
        final nextStatus = status == 'present'
            ? AttendanceStatus.present
            : AttendanceStatus.absent;
        _demoAttendance = _demoAttendance
            .map(
              (item) => item.id == entry.id
                  ? item.copyWith(status: nextStatus)
                  : item,
            )
            .toList();
      }
      setState(_reload);
      _showMessage(
        status == 'present'
            ? 'La présence a été validée.'
            : 'L’absence a été confirmée.',
      );
    } catch (error) {
      _showMessage('La validation a échoué : $error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 940;
        return Scaffold(
          drawer: desktop
              ? null
              : Drawer(
                  child: SafeArea(
                    child: _NavigationPanel(
                      selectedPage: _page,
                      role: _role,
                      userName: _displayName,
                      demoMode: widget.repository == null,
                      onNavigate: (page) {
                        _navigate(page);
                        Navigator.of(context).pop();
                      },
                      onRoleChanged: (role) => setState(() => _role = role),
                      onSignOut: widget.repository == null
                          ? null
                          : () => widget.repository!.signOut(),
                    ),
                  ),
                ),
          appBar: desktop
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  leading: Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  title: const BrandMark(compact: true),
                  actions: [
                    IconButton(
                      tooltip: _searchVisible
                          ? 'Masquer la recherche'
                          : 'Rechercher',
                      onPressed: () =>
                          setState(() => _searchVisible = !_searchVisible),
                      icon: Icon(
                        _searchVisible
                            ? Icons.search_off_rounded
                            : Icons.search_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: () =>
                          _showMessage('Aucune nouvelle notification.'),
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: _Page.values.indexOf(_page),
                  onDestinationSelected: (index) =>
                      _navigate(_Page.values[index]),
                  destinations: _Page.values
                      .map(
                        (page) => NavigationDestination(
                          icon: Icon(page.icon),
                          label: page.labelFor(_role),
                        ),
                      )
                      .toList(),
                ),
          body: Row(
            children: [
              if (desktop)
                SizedBox(
                  width: 256,
                  child: _NavigationPanel(
                    selectedPage: _page,
                    role: _role,
                    userName: _displayName,
                    demoMode: widget.repository == null,
                    onNavigate: _navigate,
                    onRoleChanged: (role) => setState(() => _role = role),
                    onSignOut: widget.repository == null
                        ? null
                        : () => widget.repository!.signOut(),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (desktop)
                      _TopBar(
                        role: _role,
                        userName: _displayName,
                        onNotification: () =>
                            _showMessage('Aucune nouvelle notification.'),
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        onClear: _clearSearch,
                      ),
                    if (!desktop && _searchVisible)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        color: Colors.white,
                        child: _SearchField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          onClear: _clearSearch,
                        ),
                      ),
                    Expanded(
                      child: FutureBuilder<List<SchoolSession>>(
                        future: _sessionsFuture,
                        builder: (context, sessionSnapshot) {
                          final allSessions =
                              sessionSnapshot.data ??
                              (widget.repository == null
                                  ? _demoSessions
                                  : const <SchoolSession>[]);
                          final sessions = _filterSessions(allSessions, _query);
                          return FutureBuilder<List<AttendanceClaim>>(
                            future: _claimsFuture,
                            builder: (context, claimSnapshot) {
                              final claims = _filterClaims(
                                claimSnapshot.data ??
                                    (widget.repository == null
                                        ? _demoClaims
                                        : const <AttendanceClaim>[]),
                                _query,
                              );
                              if (_page == _Page.overview) {
                                return FutureBuilder<List<AttendanceEntry>>(
                                  future: _attendanceFuture,
                                  builder: (context, attendanceSnapshot) {
                                    final attendance = _filterAttendance(
                                      attendanceSnapshot.data ??
                                          (widget.repository == null
                                              ? _demoAttendance
                                              : const <AttendanceEntry>[]),
                                      _query,
                                    );
                                    return _OverviewPage(
                                      role: _role,
                                      userName: _displayName,
                                      sessions: sessions,
                                      attendance: attendance,
                                      claims: claims,
                                      isLoading:
                                          sessionSnapshot.connectionState ==
                                              ConnectionState.waiting ||
                                          claimSnapshot.connectionState ==
                                              ConnectionState.waiting ||
                                          attendanceSnapshot.connectionState ==
                                              ConnectionState.waiting,
                                      error:
                                          sessionSnapshot.error ??
                                          claimSnapshot.error ??
                                          attendanceSnapshot.error,
                                      onNavigate: _navigate,
                                      onDeclare: _declareAttendance,
                                      onClaim: _openClaimForm,
                                      onResolve: _resolveClaim,
                                      onSummary: _showCourseSummary,
                                      onUploadPdf: _uploadPdfForRole,
                                    );
                                  },
                                );
                              }
                              if (_page == _Page.schedule) {
                                return _SchedulePage(
                                  role: _role,
                                  sessions: sessions,
                                  isLoading:
                                      sessionSnapshot.connectionState ==
                                      ConnectionState.waiting,
                                  error: sessionSnapshot.error,
                                  onDeclare: _declareAttendance,
                                  onSummary: _showCourseSummary,
                                  onUploadPdf: _uploadPdfForRole,
                                );
                              }
                              if (_page == _Page.attendance) {
                                return _AttendancePage(
                                  role: _role,
                                  sessions: sessions,
                                  attendanceFuture: _attendanceFuture,
                                  isLoading:
                                      sessionSnapshot.connectionState ==
                                      ConnectionState.waiting,
                                  error: sessionSnapshot.error,
                                  onDeclare: _declareAttendance,
                                  onClaim: _openClaimForm,
                                  onValidate: _validateAttendance,
                                  searchQuery: _query,
                                  onSummary: _showCourseSummary,
                                  onUploadPdf: _uploadPdfForRole,
                                );
                              }
                              return _ClaimsPage(
                                role: _role,
                                claims: claims,
                                sessions: sessions,
                                isLoading:
                                    claimSnapshot.connectionState ==
                                    ConnectionState.waiting,
                                error: claimSnapshot.error,
                                onClaim: _openClaimForm,
                                onResolve: _resolveClaim,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openClaimForm(SchoolSession? initialSession) async {
    final sessions = await _sessionsFuture;
    if (!mounted) return;
    final selectedSession = await showDialog<SchoolSession>(
      context: context,
      builder: (context) =>
          _NewClaimDialog(sessions: sessions, initialSession: initialSession),
    );
    if (selectedSession == null || !mounted) return;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const _ClaimDetailsDialog(),
    );
    if (result != null && mounted) {
      await _submitClaim(selectedSession, result.$1, result.$2);
    }
  }

  void Function(SchoolSession)? get _uploadPdfForRole =>
      _role == AppRole.student ? null : _uploadCoursePdf;

  Future<void> _showCourseSummary(SchoolSession session) async {
    final repository = widget.repository;
    if (repository == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => _LocalSummaryDialog(
          courseName: session.courseName,
          courseCode: session.courseCode,
          initialApiKey: _localApiKey,
          onApiKeyChanged: (key) => _localApiKey = key,
        ),
      );
      return;
    }
    final summaryFuture = repository.summarizeCourse(session.id);
    await showDialog<void>(
      context: context,
      builder: (context) => _SummaryDialog(
        courseName: session.courseName,
        future: summaryFuture,
      ),
    );
  }

  Future<void> _uploadCoursePdf(SchoolSession session) async {
    final repository = widget.repository;
    if (repository == null) {
      _showMessage('Mode démo : connectez Supabase pour joindre un PDF.');
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _showMessage('Impossible de lire ce fichier.', isError: true);
      return;
    }
    if (bytes.length > 10 * 1024 * 1024) {
      _showMessage('Le PDF doit faire moins de 10 Mo.', isError: true);
      return;
    }
    try {
      await repository.attachCoursePdf(
        session.id,
        fileName: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(_reload);
      _showMessage('Le PDF du cours a été joint.');
    } catch (error) {
      _showMessage('Envoi du PDF impossible : $error', isError: true);
    }
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.selectedPage,
    required this.role,
    required this.userName,
    required this.demoMode,
    required this.onNavigate,
    required this.onRoleChanged,
    required this.onSignOut,
  });

  final _Page selectedPage;
  final AppRole role;
  final String userName;
  final bool demoMode;
  final ValueChanged<_Page> onNavigate;
  final ValueChanged<AppRole> onRoleChanged;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: _line)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 34),
                child: BrandMark(),
              ),
              const _SmallLabel('MENU PRINCIPAL'),
              const SizedBox(height: 12),
              ..._Page.values.map(
                (page) => _NavItem(
                  page: page,
                  role: role,
                  selected: selectedPage == page,
                  onTap: () => onNavigate(page),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _canvas,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: _lavender,
                      child: Icon(role.icon, color: _purple, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role.label,
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (demoMode)
                      PopupMenuButton<AppRole>(
                        tooltip: 'Changer de profil démo',
                        icon: const Icon(
                          Icons.swap_horiz_rounded,
                          color: _muted,
                          size: 19,
                        ),
                        onSelected: onRoleChanged,
                        itemBuilder: (context) => AppRole.values
                            .map(
                              (value) => PopupMenuItem(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(),
                      )
                    else
                      IconButton(
                        tooltip: 'Se déconnecter',
                        onPressed: onSignOut,
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: _muted,
                          size: 19,
                        ),
                      ),
                  ],
                ),
              ),
              if (demoMode)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                    child: Text(
                      'MODE DÉMO • données de démonstration',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 9,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.page,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final _Page page;
  final AppRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? _lavender : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Icon(page.icon, size: 19, color: selected ? _purple : _muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    page.labelFor(role),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? _purpleDark : _muted,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (page == _Page.claims) ...[
                  const Spacer(),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: _orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('search_field'),
      controller: controller,
      onChanged: (_) => onChanged(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Rechercher un cours, une salle, un étudiant...',
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer la recherche',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: _canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.role,
    required this.userName,
    required this.onNotification,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final AppRole role;
  final String userName;
  final VoidCallback onNotification;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Text(
            _PageTitles.forRole(role),
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 260,
            child: _SearchField(
              controller: controller,
              onChanged: onChanged,
              onClear: onClear,
            ),
          ),
          const SizedBox(width: 18),
          IconButton(
            onPressed: onNotification,
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded, color: _muted),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 17,
            backgroundColor: _lavender,
            child: Icon(role.icon, size: 18, color: _purple),
          ),
          const SizedBox(width: 9),
          Text(
            userName,
            style: const TextStyle(
              color: _ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageTitles {
  static String forRole(AppRole role) => switch (role) {
    AppRole.student => 'Espace étudiant',
    AppRole.teacher => 'Espace enseignant',
    AppRole.director => 'Espace direction',
  };
}

class BrandMark extends StatelessWidget {
  const BrandMark({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_purple, Color(0xFF9B7CF0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.fact_check_rounded,
            color: Colors.white,
            size: 21,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          const Text(
            'présence',
            style: TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ],
    );
  }
}

class _SmallLabel extends StatelessWidget {
  const _SmallLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({
    required this.role,
    required this.userName,
    required this.sessions,
    required this.attendance,
    required this.claims,
    required this.isLoading,
    required this.error,
    required this.onNavigate,
    required this.onDeclare,
    required this.onClaim,
    required this.onResolve,
    required this.onSummary,
    required this.onUploadPdf,
  });

  final AppRole role;
  final String userName;
  final List<SchoolSession> sessions;
  final List<AttendanceEntry> attendance;
  final List<AttendanceClaim> claims;
  final bool isLoading;
  final Object? error;
  final ValueChanged<_Page> onNavigate;
  final void Function(SchoolSession, bool) onDeclare;
  final ValueChanged<SchoolSession?> onClaim;
  final void Function(AttendanceClaim, String) onResolve;
  final void Function(SchoolSession) onSummary;
  final void Function(SchoolSession)? onUploadPdf;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeHeader(
            role: role,
            userName: userName,
            onClaim: () => onClaim(null),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 850
                  ? 4
                  : constraints.maxWidth >= 530
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - 14 * (columns - 1)) / columns;
              final metrics = _metricsFor(role, sessions, attendance, claims);
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: metrics
                    .map(
                      (metric) => SizedBox(
                        width: width,
                        child: _MetricCard(metric: metric),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 28),
          if (error != null) _ErrorBanner(message: error.toString()),
          if (isLoading) const _LoadingLine(),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              final schedule = _SchedulePreview(
                sessions: sessions,
                role: role,
                onViewAll: () => onNavigate(_Page.schedule),
                onDeclare: onDeclare,
                onSummary: onSummary,
                onUploadPdf: onUploadPdf,
              );
              final claimsPreview = _ClaimsPreview(
                claims: claims,
                role: role,
                onViewAll: () => onNavigate(_Page.claims),
                onResolve: onResolve,
              );
              if (stacked) {
                return Column(
                  children: [
                    schedule,
                    const SizedBox(height: 18),
                    claimsPreview,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: schedule),
                  const SizedBox(width: 18),
                  Expanded(flex: 4, child: claimsPreview),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

List<_Metric> _metricsFor(
  AppRole role,
  List<SchoolSession> sessions,
  List<AttendanceEntry> attendance,
  List<AttendanceClaim> claims,
) {
  final confirmed = attendance
      .where(
        (entry) =>
            entry.status == AttendanceStatus.present ||
            entry.status == AttendanceStatus.absent ||
            entry.status == AttendanceStatus.late,
      )
      .toList();
  final present = confirmed
      .where(
        (entry) =>
            entry.status == AttendanceStatus.present ||
            entry.status == AttendanceStatus.late,
      )
      .length;
  final absences = confirmed
      .where((entry) => entry.status == AttendanceStatus.absent)
      .length;
  final rate = confirmed.isEmpty ? 0.0 : present / confirmed.length;
  final pendingAttendance = attendance
      .where(
        (entry) =>
            entry.status == AttendanceStatus.declared ||
            entry.status == AttendanceStatus.declaredAbsent,
      )
      .length;
  final pendingClaims = claims
      .where((claim) => claim.status == 'pending')
      .length;
  final studentCount = attendance
      .map((entry) => entry.studentName)
      .toSet()
      .length;
  final percent = '${(rate * 100).round()} %';

  return switch (role) {
    AppRole.student => [
      _Metric(
        'Taux de présence',
        percent,
        '$present présence(s) sur ${confirmed.length} séance(s) validée(s)',
        Icons.trending_up_rounded,
        _green,
        rate,
      ),
      _Metric(
        'Cours suivis',
        '$present',
        '${attendance.length} séance(s) enregistrée(s)',
        Icons.menu_book_outlined,
        _purple,
        null,
      ),
      _Metric(
        'Absences',
        '$absences',
        'absence(s) confirmée(s)',
        Icons.event_busy_outlined,
        _orange,
        null,
      ),
      _Metric(
        'Réclamations',
        '$pendingClaims',
        'en cours de traitement',
        Icons.chat_bubble_outline_rounded,
        const Color(0xFF6386CF),
        null,
      ),
    ],
    AppRole.teacher => [
      _Metric(
        'Séances cette semaine',
        '${sessions.length}',
        'dans vos classes',
        Icons.menu_book_outlined,
        _purple,
        null,
      ),
      _Metric(
        'Étudiants',
        '$studentCount',
        'avec une présence enregistrée',
        Icons.groups_outlined,
        const Color(0xFF6386CF),
        null,
      ),
      _Metric(
        'À valider',
        '$pendingAttendance',
        'déclaration(s) reçue(s)',
        Icons.fact_check_outlined,
        _orange,
        null,
      ),
      _Metric(
        'Réclamations',
        '$pendingClaims',
        'à examiner',
        Icons.chat_bubble_outline_rounded,
        _green,
        null,
      ),
    ],
    AppRole.director => [
      _Metric(
        'Présence globale',
        percent,
        '${confirmed.length} séance(s) validée(s)',
        Icons.trending_up_rounded,
        _green,
        rate,
      ),
      _Metric(
        'Étudiants actifs',
        '$studentCount',
        'avec une présence enregistrée',
        Icons.groups_outlined,
        _purple,
        null,
      ),
      _Metric(
        'Absences confirmées',
        '$absences',
        'toutes classes confondues',
        Icons.event_busy_outlined,
        _orange,
        null,
      ),
      _Metric(
        'Litiges ouverts',
        '$pendingClaims',
        'décision requise',
        Icons.gavel_rounded,
        const Color(0xFF6386CF),
        null,
      ),
    ],
  };
}

class _Metric {
  const _Metric(
    this.label,
    this.value,
    this.note,
    this.icon,
    this.color,
    this.progress,
  );

  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;
  final double? progress;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metric.label,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: metric.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(metric.icon, size: 17, color: metric.color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                metric.value,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 25,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              if (metric.progress != null) ...[
                const Spacer(),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    value: metric.progress,
                    strokeWidth: 4,
                    backgroundColor: _lavender,
                    color: metric.color,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            metric.note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.role,
    required this.userName,
    required this.onClaim,
  });

  final AppRole role;
  final String userName;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final greeting = switch (role) {
      AppRole.student => 'Bonjour $userName 👋',
      AppRole.teacher => 'Bonjour $userName 👋',
      AppRole.director => 'Bonjour $userName 👋',
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 570;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(greeting, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 5),
            const Text(
              'Voici le résumé de votre activité pour aujourd’hui.',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: _purple,
                ),
                const SizedBox(width: 7),
                Text(
                  _frenchDate(DateTime.now()),
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        );
        final action = role == AppRole.student
            ? FilledButton.icon(
                onPressed: onClaim,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Nouvelle réclamation'),
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              )
            : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: action == null
              ? content
              : compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [content, const SizedBox(height: 14), action],
                )
              : Row(
                  children: [
                    Expanded(child: content),
                    action,
                  ],
                ),
        );
      },
    );
  }
}

String _frenchDate(DateTime date) {
  const weekdays = [
    'Dimanche',
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
  ];
  const months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  return '${weekdays[date.weekday % 7]} ${date.day} ${months[date.month - 1]} ${date.year}';
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1150),
          child: child,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
    ),
    child: child,
  );
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      TextButton(
        onPressed: onAction,
        style: TextButton.styleFrom(
          foregroundColor: _purple,
          padding: const EdgeInsets.symmetric(horizontal: 7),
        ),
        child: Text(
          actionLabel,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _SchedulePreview extends StatelessWidget {
  const _SchedulePreview({
    required this.sessions,
    required this.role,
    required this.onViewAll,
    required this.onDeclare,
    required this.onSummary,
    required this.onUploadPdf,
  });

  final List<SchoolSession> sessions;
  final AppRole role;
  final VoidCallback onViewAll;
  final void Function(SchoolSession, bool) onDeclare;
  final void Function(SchoolSession) onSummary;
  final void Function(SchoolSession)? onUploadPdf;

  @override
  Widget build(BuildContext context) {
    final items = sessions.take(3).toList();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeading(
            title: role == AppRole.student
                ? 'Mon emploi du temps'
                : 'Séances du jour',
            actionLabel: 'Tout voir',
            onAction: onViewAll,
          ),
          const Divider(height: 18, color: _line),
          if (items.isEmpty)
            const _EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'Aucune séance à afficher',
            )
          else
            ...items.map(
              (session) => _SessionTile(
                session: session,
                compact: true,
                onDeclarePresent: role == AppRole.student
                    ? () => onDeclare(session, true)
                    : null,
                onDeclareAbsent: role == AppRole.student
                    ? () => onDeclare(session, false)
                    : null,
                onSummary: () => onSummary(session),
                onUploadPdf: onUploadPdf == null
                    ? null
                    : () => onUploadPdf!(session),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClaimsPreview extends StatelessWidget {
  const _ClaimsPreview({
    required this.claims,
    required this.role,
    required this.onViewAll,
    required this.onResolve,
  });

  final List<AttendanceClaim> claims;
  final AppRole role;
  final VoidCallback onViewAll;
  final void Function(AttendanceClaim, String) onResolve;

  @override
  Widget build(BuildContext context) {
    final pending = claims.where((claim) => claim.status == 'pending').toList();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeading(
            title: role == AppRole.student
                ? 'Mes réclamations'
                : 'Réclamations à traiter',
            actionLabel: 'Tout voir',
            onAction: onViewAll,
          ),
          const Divider(height: 18, color: _line),
          if (pending.isEmpty)
            const _EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'Tout est à jour !',
            )
          else
            ...pending
                .take(2)
                .map(
                  (claim) => _ClaimTile(
                    claim: claim,
                    canResolve: role != AppRole.student,
                    onResolve: (status) => onResolve(claim, status),
                  ),
                ),
        ],
      ),
    );
  }
}

class _SchedulePage extends StatefulWidget {
  const _SchedulePage({
    required this.role,
    required this.sessions,
    required this.isLoading,
    required this.error,
    required this.onDeclare,
    required this.onSummary,
    required this.onUploadPdf,
  });

  final AppRole role;
  final List<SchoolSession> sessions;
  final bool isLoading;
  final Object? error;
  final void Function(SchoolSession, bool) onDeclare;
  final void Function(SchoolSession) onSummary;
  final void Function(SchoolSession)? onUploadPdf;

  @override
  State<_SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<_SchedulePage> {
  int _selectedDay = DateTime.now().weekday <= 5 ? DateTime.now().weekday : 1;

  @override
  Widget build(BuildContext context) {
    final monday = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );
    final days = List.generate(5, (index) => monday.add(Duration(days: index)));
    final selected = days[_selectedDay - 1];
    final sessions =
        widget.sessions
            .where(
              (session) =>
                  session.startsAt.year == selected.year &&
                  session.startsAt.month == selected.month &&
                  session.startsAt.day == selected.day,
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeading(
            title: 'Emploi du temps',
            subtitle: 'Consultez vos séances et déclarez votre présence.',
          ),
          if (widget.error != null) _ErrorBanner(message: '${widget.error}'),
          if (widget.isLoading) const _LoadingLine(),
          const SizedBox(height: 20),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Cette semaine',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${_monthName(selected.month)} ${selected.year}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 32) / 5;
                    return Row(
                      children: List.generate(days.length, (index) {
                        final day = days[index];
                        final isSelected = _selectedDay == index + 1;
                        return Padding(
                          padding: EdgeInsets.only(right: index == 4 ? 0 : 8),
                          child: SizedBox(
                            width: width,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () =>
                                  setState(() => _selectedDay = index + 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected ? _purple : _canvas,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      _weekdayShort(day.weekday),
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white70
                                            : _muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : _ink,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sessions.length} séance${sessions.length > 1 ? 's' : ''} • ${_weekdayLong(selected.weekday)} ${selected.day}',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (sessions.isEmpty)
                  const _EmptyState(
                    icon: Icons.event_available_outlined,
                    title: 'Aucune séance prévue ce jour-là',
                  )
                else
                  ...sessions.map(
                    (session) => _SessionTile(
                      session: session,
                      onDeclarePresent: widget.role == AppRole.student
                          ? () => widget.onDeclare(session, true)
                          : null,
                      onDeclareAbsent: widget.role == AppRole.student
                          ? () => widget.onDeclare(session, false)
                          : null,
                      onSummary: () => widget.onSummary(session),
                      onUploadPdf: widget.onUploadPdf == null
                          ? null
                          : () => widget.onUploadPdf!(session),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendancePage extends StatelessWidget {
  const _AttendancePage({
    required this.role,
    required this.sessions,
    required this.attendanceFuture,
    required this.isLoading,
    required this.error,
    required this.onDeclare,
    required this.onClaim,
    required this.onValidate,
    required this.searchQuery,
    required this.onSummary,
    required this.onUploadPdf,
  });

  final AppRole role;
  final List<SchoolSession> sessions;
  final Future<List<AttendanceEntry>> attendanceFuture;
  final bool isLoading;
  final Object? error;
  final void Function(SchoolSession, bool) onDeclare;
  final ValueChanged<SchoolSession?> onClaim;
  final void Function(AttendanceEntry, String) onValidate;
  final String searchQuery;
  final void Function(SchoolSession) onSummary;
  final void Function(SchoolSession)? onUploadPdf;

  @override
  Widget build(BuildContext context) {
    if (role != AppRole.student) {
      return FutureBuilder<List<AttendanceEntry>>(
        future: attendanceFuture,
        builder: (context, snapshot) => _TeacherValidationPage(
          entries: _filterAttendance(snapshot.data ?? const [], searchQuery),
          isLoading: snapshot.connectionState == ConnectionState.waiting,
          error: snapshot.error,
          onValidate: onValidate,
        ),
      );
    }
    final present = sessions
        .where((session) => session.status == AttendanceStatus.present)
        .length;
    final attendanceRate = sessions.isEmpty
        ? 0
        : (present / sessions.length * 100).round();
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeading(
            title: 'Suivi de présence',
            subtitle:
                'Consultez vos déclarations et signalez une erreur à votre enseignant.',
            action: OutlinedButton.icon(
              onPressed: () => onClaim(null),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Contester une absence'),
            ),
          ),
          if (error != null) _ErrorBanner(message: '$error'),
          if (isLoading) const _LoadingLine(),
          const SizedBox(height: 16),
          _Panel(
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: sessions.isEmpty ? 0 : attendanceRate / 100,
                    strokeWidth: 5,
                    backgroundColor: _lavender,
                    color: _purple,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Taux de présence',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$attendanceRate %',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${sessions.length} séances',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Historique des séances',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (sessions.isEmpty)
                  const _EmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'Aucune séance à afficher',
                  )
                else
                  ...sessions.map(
                    (session) => _SessionTile(
                      session: session,
                      onDeclarePresent: () => onDeclare(session, true),
                      onDeclareAbsent: () => onDeclare(session, false),
                      onClaim: () => onClaim(session),
                      onSummary: () => onSummary(session),
                      onUploadPdf: onUploadPdf == null
                          ? null
                          : () => onUploadPdf!(session),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherValidationPage extends StatelessWidget {
  const _TeacherValidationPage({
    required this.entries,
    required this.isLoading,
    required this.error,
    required this.onValidate,
  });

  final List<AttendanceEntry> entries;
  final bool isLoading;
  final Object? error;
  final void Function(AttendanceEntry, String) onValidate;

  @override
  Widget build(BuildContext context) {
    final awaiting = entries
        .where(
          (entry) =>
              entry.status == AttendanceStatus.declared ||
              entry.status == AttendanceStatus.declaredAbsent,
        )
        .length;
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeading(
            title: 'Validation des présences',
            subtitle:
                'Examinez les déclarations des étudiants et confirmez les feuilles d’appel.',
          ),
          if (error != null) _ErrorBanner(message: '$error'),
          if (isLoading) const _LoadingLine(),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  metric: _Metric(
                    'Déclarations à valider',
                    '$awaiting',
                    'en attente de confirmation',
                    Icons.fact_check_outlined,
                    _orange,
                    null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Déclarations des étudiants',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  const _EmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'Aucune déclaration à afficher',
                  )
                else
                  ...entries.map(
                    (entry) => _AttendanceEntryTile(
                      entry: entry,
                      onValidate: (status) => onValidate(entry, status),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceEntryTile extends StatelessWidget {
  const _AttendanceEntryTile({required this.entry, required this.onValidate});

  final AttendanceEntry entry;
  final ValueChanged<String> onValidate;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(entry.status);
    final pending =
        entry.status == AttendanceStatus.declared ||
        entry.status == AttendanceStatus.declaredAbsent;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 600;
          final identity = Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: _lavender,
                child: Text(
                  entry.studentName.isEmpty ? '?' : entry.studentName[0],
                  style: const TextStyle(
                    color: _purple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.courseName} • ${_shortDate(entry.startsAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          );
          final decision = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusBadge(label: status.label, color: status.color),
              if (pending) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Confirmer l’absence',
                  onPressed: () => onValidate('absent'),
                  icon: const Icon(Icons.close_rounded, color: _red, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Valider la présence',
                  onPressed: () => onValidate('present'),
                  icon: const Icon(
                    Icons.check_rounded,
                    color: _green,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          );
          return narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: decision),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    decision,
                  ],
                );
        },
      ),
    );
  }
}

class _ClaimsPage extends StatelessWidget {
  const _ClaimsPage({
    required this.role,
    required this.claims,
    required this.sessions,
    required this.isLoading,
    required this.error,
    required this.onClaim,
    required this.onResolve,
  });

  final AppRole role;
  final List<AttendanceClaim> claims;
  final List<SchoolSession> sessions;
  final bool isLoading;
  final Object? error;
  final ValueChanged<SchoolSession?> onClaim;
  final void Function(AttendanceClaim, String) onResolve;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeading(
            title: role == AppRole.student
                ? 'Mes réclamations'
                : 'Gestion des réclamations',
            subtitle: role == AppRole.student
                ? 'Suivez le traitement de vos demandes de correction.'
                : 'Examinez les contestations et enregistrez votre décision.',
            action: role == AppRole.student
                ? FilledButton.icon(
                    onPressed: () => onClaim(null),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Nouvelle réclamation'),
                  )
                : null,
          ),
          if (error != null) _ErrorBanner(message: '$error'),
          if (isLoading) const _LoadingLine(),
          _Panel(
            child: claims.isEmpty
                ? const _EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Aucune réclamation',
                  )
                : Column(
                    children: claims
                        .map(
                          (claim) => _ClaimTile(
                            claim: claim,
                            canResolve:
                                role != AppRole.student &&
                                claim.status == 'pending',
                            onResolve: (status) => onResolve(claim, status),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 13)),
        ],
      );
      if (action == null) return heading;
      if (constraints.maxWidth < 620) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 14), action!],
        );
      }
      return Row(
        children: [
          Expanded(child: heading),
          action!,
        ],
      );
    },
  );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    this.compact = false,
    this.onDeclarePresent,
    this.onDeclareAbsent,
    this.onClaim,
    this.onSummary,
    this.onUploadPdf,
  });

  final SchoolSession session;
  final bool compact;
  final VoidCallback? onDeclarePresent;
  final VoidCallback? onDeclareAbsent;
  final VoidCallback? onClaim;
  final VoidCallback? onSummary;
  final VoidCallback? onUploadPdf;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(session.status);
    return Container(
      padding: EdgeInsets.symmetric(vertical: compact ? 11 : 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: status.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 13),
          SizedBox(
            width: 48,
            child: Text(
              '${_twoDigits(session.startsAt.hour)}:${_twoDigits(session.startsAt.minute)}',
              style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  compact
                      ? '${session.room}  •  ${session.teacherName}'
                      : '${_weekdayLong(session.startsAt.weekday)} ${session.startsAt.day} ${_monthName(session.startsAt.month)}  •  ${session.room}  •  ${session.teacherName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusBadge(label: status.label, color: status.color),
          if (onDeclarePresent != null ||
              onDeclareAbsent != null ||
              onClaim != null ||
              onSummary != null ||
              onUploadPdf != null) ...[
            const SizedBox(width: 5),
            PopupMenuButton<String>(
              tooltip: 'Actions sur la séance',
              icon: const Icon(Icons.more_horiz_rounded, color: _muted),
              onSelected: (action) {
                if (action == 'present') onDeclarePresent?.call();
                if (action == 'absent') onDeclareAbsent?.call();
                if (action == 'claim') onClaim?.call();
                if (action == 'summary') onSummary?.call();
                if (action == 'pdf') onUploadPdf?.call();
              },
              itemBuilder: (context) => [
                if (onSummary != null)
                  const PopupMenuItem(
                    value: 'summary',
                    child: Text('Résumé IA du cours'),
                  ),
                if (onUploadPdf != null)
                  const PopupMenuItem(
                    value: 'pdf',
                    child: Text('Joindre un PDF'),
                  ),
                if ((onDeclarePresent != null || onDeclareAbsent != null) &&
                    session.status != AttendanceStatus.declared &&
                    session.status != AttendanceStatus.declaredAbsent)
                  const PopupMenuItem(
                    value: 'present',
                    child: Text('Déclarer ma présence'),
                  ),
                if ((onDeclarePresent != null || onDeclareAbsent != null) &&
                    session.status != AttendanceStatus.declared &&
                    session.status != AttendanceStatus.declaredAbsent)
                  const PopupMenuItem(
                    value: 'absent',
                    child: Text('Déclarer mon absence'),
                  ),
                if (onClaim != null)
                  const PopupMenuItem(
                    value: 'claim',
                    child: Text('Contester cette absence'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusInfo {
  const _StatusInfo(this.label, this.color);
  final String label;
  final Color color;
}

_StatusInfo _statusFor(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => const _StatusInfo('Présent', _green),
  AttendanceStatus.absent => const _StatusInfo('Absent', _red),
  AttendanceStatus.late => const _StatusInfo('En retard', _orange),
  AttendanceStatus.declared => const _StatusInfo('À valider', _orange),
  AttendanceStatus.declaredAbsent => const _StatusInfo(
    'Absence à valider',
    _orange,
  ),
  AttendanceStatus.pending => const _StatusInfo('À confirmer', _muted),
};

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({
    required this.claim,
    required this.canResolve,
    required this.onResolve,
  });

  final AttendanceClaim claim;
  final bool canResolve;
  final ValueChanged<String> onResolve;

  @override
  Widget build(BuildContext context) {
    final status = switch (claim.status) {
      'approved' => const _StatusInfo('Acceptée', _green),
      'rejected' => const _StatusInfo('Refusée', _red),
      _ => const _StatusInfo('En attente', _orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _lavender,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: _purple,
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      claim.courseName,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${claim.reason} • ${_shortDate(claim.createdAt)}',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              _StatusBadge(label: status.label, color: status.color),
            ],
          ),
          if (claim.details.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              claim.details,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
          if (canResolve && claim.status == 'pending') ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => onResolve('rejected'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: Color(0xFFF3DADD)),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Refuser'),
                ),
                FilledButton(
                  onPressed: () => onResolve('approved'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Accepter'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NewClaimDialog extends StatefulWidget {
  const _NewClaimDialog({required this.sessions, this.initialSession});
  final List<SchoolSession> sessions;
  final SchoolSession? initialSession;

  @override
  State<_NewClaimDialog> createState() => _NewClaimDialogState();
}

class _NewClaimDialogState extends State<_NewClaimDialog> {
  SchoolSession? _selected;

  @override
  void initState() {
    super.initState();
    _selected =
        widget.initialSession ??
        (widget.sessions.isEmpty ? null : widget.sessions.first);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Contester une absence'),
      content: SizedBox(
        width: 390,
        child: widget.sessions.isEmpty
            ? const Text('Aucune séance disponible pour une réclamation.')
            : DropdownButtonFormField<SchoolSession>(
                initialValue: _selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Séance concernée',
                ),
                items: widget.sessions
                    .map(
                      (session) => DropdownMenuItem(
                        value: session,
                        child: Text(
                          '${session.courseName} • ${_shortDate(session.startsAt)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selected = value),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}

class _ClaimDetailsDialog extends StatefulWidget {
  const _ClaimDetailsDialog();

  @override
  State<_ClaimDetailsDialog> createState() => _ClaimDetailsDialogState();
}

class _ClaimDetailsDialogState extends State<_ClaimDetailsDialog> {
  final _details = TextEditingController();
  String _reason = 'Présent en cours';

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Détails de la réclamation'),
    content: SizedBox(
      width: 390,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _reason,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Motif'),
            items:
                const [
                      'Présent en cours',
                      'Erreur de saisie',
                      'Justificatif médical',
                      'Autre motif',
                    ]
                    .map(
                      (reason) =>
                          DropdownMenuItem(value: reason, child: Text(reason)),
                    )
                    .toList(),
            onChanged: (value) => setState(() => _reason = value ?? _reason),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _details,
            onChanged: (_) => setState(() {}),
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Expliquez votre demande',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _details.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (_reason, _details.text.trim())),
        child: const Text('Envoyer'),
      ),
    ],
  );
}

class _LocalSummaryDialog extends StatefulWidget {
  const _LocalSummaryDialog({
    required this.courseName,
    required this.courseCode,
    required this.initialApiKey,
    required this.onApiKeyChanged,
  });

  final String courseName;
  final String courseCode;
  final String initialApiKey;
  final ValueChanged<String> onApiKeyChanged;

  @override
  State<_LocalSummaryDialog> createState() => _LocalSummaryDialogState();
}

class _LocalSummaryDialogState extends State<_LocalSummaryDialog> {
  late final TextEditingController _keyController;
  Uint8List? _pdfBytes;
  String? _pdfName;
  String? _error;
  String? _summary;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initialApiKey);
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null) {
      setState(() => _error = 'Impossible de lire ce fichier.');
      return;
    }
    setState(() {
      _pdfBytes = file.bytes;
      _pdfName = file.name;
      _error = null;
    });
  }

  Future<void> _generate() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    final key = _keyController.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    widget.onApiKeyChanged(key);
    try {
      final summary = await GeminiSummaryService(key).summarize(
        courseName: widget.courseName,
        courseCode: widget.courseCode,
        pdfBytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Résumé IA • ${widget.courseName}'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: _summary == null
            ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialApiKey.isEmpty
                      ? 'Sans Supabase : collez votre clé gratuite et choisissez '
                          'le PDF du cours. La clé reste en mémoire dans l’application.'
                      : 'Sans Supabase : choisissez le PDF du cours. La clé est '
                          'fournie au lancement de l’application.',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                if (widget.initialApiKey.isEmpty)
                  TextField(
                    controller: _keyController,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Clé Google AI Studio (gratuite)',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  )
                else
                  const InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Clé Gemini intégrée au build',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('Disponible pour cette session'),
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickPdf,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Choisir un PDF'),
                ),
                const SizedBox(height: 8),
                Text(
                  _pdfName ?? 'Aucun PDF sélectionné',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: _red)),
                ],
              ],
            )
            : SelectableText(
              _summary!,
              style: const TextStyle(color: _ink, fontSize: 13, height: 1.5),
            ),
      ),
    ),
    actions: [
      if (_summary == null)
        FilledButton(
          onPressed:
              _loading ||
                  _pdfBytes == null ||
                  _keyController.text.trim().isEmpty
              ? null
              : _generate,
          child: Text(_loading ? 'Génération...' : 'Générer le résumé'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
    ],
  );
}

class _SummaryDialog extends StatelessWidget {
  const _SummaryDialog({required this.courseName, required this.future});

  final String courseName;
  final Future<Map<String, dynamic>> future;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Résumé IA • $courseName'),
    content: SizedBox(
      width: 460,
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: CircularProgressIndicator(color: _purple),
              ),
            );
          }
          if (snapshot.hasError) {
            return Text(
              'Résumé indisponible : ${snapshot.error}\n\n'
              'Le service Supabase IA est peut-être encore en attente de déploiement.',
              style: const TextStyle(color: _red),
            );
          }
          final summary = snapshot.data?['summary'] as String? ?? '';
          final cached = snapshot.data?['cached'] == true;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cached)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Résumé déjà généré pour ce PDF.',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ),
                SelectableText(
                  summary,
                  style: const TextStyle(color: _ink, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Column(
        children: [
          Icon(icon, color: _muted, size: 25),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    ),
  );
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: _lavender,
      color: _purple,
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: _red, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: _red, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

bool _contains(String value, String query) =>
    value.toLowerCase().contains(query);

List<SchoolSession> _filterSessions(
  List<SchoolSession> sessions,
  String query,
) {
  if (query.isEmpty) return sessions;
  return sessions
      .where(
        (session) =>
            _contains(session.courseName, query) ||
            _contains(session.courseCode, query) ||
            _contains(session.room, query) ||
            _contains(session.teacherName, query) ||
            _contains(_statusFor(session.status).label, query),
      )
      .toList();
}

List<AttendanceClaim> _filterClaims(
  List<AttendanceClaim> claims,
  String query,
) {
  if (query.isEmpty) return claims;
  return claims
      .where(
        (claim) =>
            _contains(claim.courseName, query) ||
            _contains(claim.reason, query) ||
            _contains(claim.details, query) ||
            _contains(claim.status, query),
      )
      .toList();
}

List<AttendanceEntry> _filterAttendance(
  List<AttendanceEntry> entries,
  String query,
) {
  if (query.isEmpty) return entries;
  return entries
      .where(
        (entry) =>
            _contains(entry.studentName, query) ||
            _contains(entry.courseName, query) ||
            _contains(_statusFor(entry.status).label, query),
      )
      .toList();
}

String _shortDate(DateTime date) =>
    '${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _monthName(int month) => const [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
][month - 1];

String _weekdayShort(int day) =>
    const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'][day - 1];

String _weekdayLong(int day) => const [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
][day - 1];

final _today = DateTime.now();
final demoSessions = [
  SchoolSession(
    id: 'demo-session-1',
    courseName: 'Algorithmique avancée',
    courseCode: 'INF-204',
    teacherName: 'Mme Linda Wadaa',
    room: 'Salle B12',
    startsAt: DateTime(_today.year, _today.month, _today.day, 8, 30),
  ),
  SchoolSession(
    id: 'demo-session-2',
    courseName: 'Bases de données',
    courseCode: 'INF-216',
    teacherName: 'Mme Linda Wadaa',
    room: 'Labo 03',
    startsAt: DateTime(_today.year, _today.month, _today.day, 10, 30),
    status: AttendanceStatus.declared,
  ),
  SchoolSession(
    id: 'demo-session-3',
    courseName: 'Réseaux informatiques',
    courseCode: 'INF-220',
    teacherName: 'Mme Linda Wadaa',
    room: 'Salle A05',
    startsAt: DateTime(_today.year, _today.month, _today.day, 14, 0),
  ),
  SchoolSession(
    id: 'demo-session-4',
    courseName: 'Développement mobile',
    courseCode: 'INF-231',
    teacherName: 'Mme Linda Wadaa',
    room: 'Labo 02',
    startsAt: DateTime(_today.year, _today.month, _today.day, 16, 0),
  ),
];

final demoClaims = [
  AttendanceClaim(
    id: 'demo-claim-1',
    sessionId: 'demo-session-1',
    courseName: 'Algorithmique avancée',
    reason: 'Présent en cours',
    details:
        'J’étais présent le jour du contrôle, mais mon absence apparaît dans le relevé.',
    status: 'pending',
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  AttendanceClaim(
    id: 'demo-claim-2',
    sessionId: 'demo-session-2',
    courseName: 'Bases de données',
    reason: 'Erreur de saisie',
    details: 'Un justificatif a été remis au secrétariat.',
    status: 'approved',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  AttendanceClaim(
    id: 'demo-claim-3',
    sessionId: 'demo-session-3',
    courseName: 'Réseaux informatiques',
    reason: 'Présent en cours',
    details: 'Je suis arrivé à l’heure, veuillez vérifier la feuille.',
    status: 'pending',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
  ),
];

final demoAttendanceEntries = [
  AttendanceEntry(
    id: 'demo-attendance-1',
    sessionId: 'demo-session-1',
    studentName: 'Dina Jouini',
    courseName: 'Algorithmique avancée',
    startsAt: _today,
    status: AttendanceStatus.declared,
  ),
  AttendanceEntry(
    id: 'demo-attendance-2',
    sessionId: 'demo-session-2',
    studentName: 'Omar Benali',
    courseName: 'Bases de données',
    startsAt: _today,
    status: AttendanceStatus.declared,
  ),
  AttendanceEntry(
    id: 'demo-attendance-3',
    sessionId: 'demo-session-3',
    studentName: 'Lina Chraïbi',
    courseName: 'Réseaux informatiques',
    startsAt: _today,
    status: AttendanceStatus.present,
  ),
];
