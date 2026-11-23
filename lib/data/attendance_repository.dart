import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

enum AttendanceStatus {
  pending,
  declared,
  declaredAbsent,
  present,
  absent,
  late,
}

class AttendanceEntry {
  const AttendanceEntry({
    required this.id,
    required this.sessionId,
    required this.studentName,
    required this.courseName,
    required this.startsAt,
    required this.status,
  });

  final String id;
  final String sessionId;
  final String studentName;
  final String courseName;
  final DateTime startsAt;
  final AttendanceStatus status;

  AttendanceEntry copyWith({AttendanceStatus? status}) => AttendanceEntry(
    id: id,
    sessionId: sessionId,
    studentName: studentName,
    courseName: courseName,
    startsAt: startsAt,
    status: status ?? this.status,
  );

  factory AttendanceEntry.fromMap(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map<String, dynamic>?;
    final session = row['sessions'] as Map<String, dynamic>?;
    final status = switch (row['status']) {
      'present' => AttendanceStatus.present,
      'absent' => AttendanceStatus.absent,
      'late' => AttendanceStatus.late,
      'declared_present' => AttendanceStatus.declared,
      'declared_absent' => AttendanceStatus.declaredAbsent,
      _ => AttendanceStatus.pending,
    };
    return AttendanceEntry(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      studentName: profile?['full_name'] as String? ?? 'Étudiant',
      courseName: session?['course_name'] as String? ?? 'Cours',
      startsAt: DateTime.parse(session?['starts_at'] as String).toLocal(),
      status: status,
    );
  }
}

class SchoolSession {
  const SchoolSession({
    required this.id,
    required this.courseName,
    required this.courseCode,
    required this.teacherName,
    required this.room,
    required this.startsAt,
    this.status = AttendanceStatus.pending,
  });

  final String id;
  final String courseName;
  final String courseCode;
  final String teacherName;
  final String room;
  final DateTime startsAt;
  final AttendanceStatus status;

  SchoolSession copyWith({AttendanceStatus? status}) => SchoolSession(
    id: id,
    courseName: courseName,
    courseCode: courseCode,
    teacherName: teacherName,
    room: room,
    startsAt: startsAt,
    status: status ?? this.status,
  );

  factory SchoolSession.fromMap(
    Map<String, dynamic> row, {
    AttendanceStatus status = AttendanceStatus.pending,
  }) {
    return SchoolSession(
      id: row['id'] as String,
      courseName: row['course_name'] as String? ?? 'Cours',
      courseCode: row['course_code'] as String? ?? '',
      teacherName: row['teacher_name'] as String? ?? 'Enseignant',
      room: row['room'] as String? ?? 'Salle à confirmer',
      startsAt: DateTime.parse(row['starts_at'] as String).toLocal(),
      status: status,
    );
  }
}

class AttendanceClaim {
  const AttendanceClaim({
    required this.id,
    required this.sessionId,
    required this.courseName,
    required this.reason,
    required this.details,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String courseName;
  final String reason;
  final String details;
  final String status;
  final DateTime createdAt;

  AttendanceClaim copyWith({String? status}) => AttendanceClaim(
    id: id,
    sessionId: sessionId,
    courseName: courseName,
    reason: reason,
    details: details,
    status: status ?? this.status,
    createdAt: createdAt,
  );

  factory AttendanceClaim.fromMap(Map<String, dynamic> row) {
    return AttendanceClaim(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      courseName: row['course_name'] as String? ?? 'Cours',
      reason: row['reason'] as String,
      details: row['details'] as String? ?? '',
      status: row['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }
}

String _aiErrorMessage(Object error) {
  final text = error.toString();
  final match =
      RegExp(r'error:\s*([^}\)]+)').firstMatch(text) ??
      RegExp(r'message:\s*([^}\)]+)').firstMatch(text);
  return match?.group(1)?.trim() ?? 'Le service IA est indisponible.';
}

class AttendanceRepository {
  AttendanceRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Une session utilisateur est requise.');
    }
    return id;
  }

  Future<List<SchoolSession>> loadSessions() async {
    final rows = await _client
        .from('sessions')
        .select('id, course_name, course_code, teacher_name, room, starts_at')
        .order('starts_at');
    final attendanceRows = await _client
        .from('attendance_records')
        .select('session_id, status')
        .eq('student_id', _userId);
    final statuses = <String, AttendanceStatus>{};
    for (final row in attendanceRows) {
      final status = switch (row['status']) {
        'present' => AttendanceStatus.present,
        'absent' => AttendanceStatus.absent,
        'late' => AttendanceStatus.late,
        'declared_present' => AttendanceStatus.declared,
        'declared_absent' => AttendanceStatus.declaredAbsent,
        _ => AttendanceStatus.pending,
      };
      statuses[row['session_id'] as String] = status;
    }
    return rows
        .map(
          (row) => SchoolSession.fromMap(
            row,
            status: statuses[row['id'] as String] ?? AttendanceStatus.pending,
          ),
        )
        .toList();
  }

  Future<List<AttendanceClaim>> loadClaims() async {
    final rows = await _client
        .from('claims')
        .select(
          'id, session_id, course_name, reason, details, status, created_at',
        )
        .order('created_at', ascending: false);
    return rows.map(AttendanceClaim.fromMap).toList();
  }

  Future<List<AttendanceEntry>> loadAttendanceRecords() async {
    final rows = await _client
        .from('attendance_records')
        .select(
          'id, session_id, student_id, status, profiles!attendance_records_student_id_fkey(full_name), sessions!attendance_records_session_id_fkey(course_name, starts_at)',
        );
    return rows.map(AttendanceEntry.fromMap).toList();
  }

  Future<void> declareAttendance(
    String sessionId, {
    required bool present,
  }) async {
    await _client.from('attendance_records').upsert({
      'session_id': sessionId,
      'student_id': _userId,
      'status': present ? 'declared_present' : 'declared_absent',
      'marked_by': _userId,
    }, onConflict: 'session_id,student_id');
  }

  Future<void> submitClaim(
    String sessionId, {
    required String reason,
    required String details,
  }) async {
    final session = await _client
        .from('sessions')
        .select('course_name')
        .eq('id', sessionId)
        .single();
    await _client.from('claims').insert({
      'session_id': sessionId,
      'student_id': _userId,
      'course_name': session['course_name'],
      'reason': reason,
      'details': details,
    });
  }

  Future<void> resolveClaim(String claimId, String status) async {
    if (status != 'approved' && status != 'rejected') {
      throw ArgumentError.value(status, 'status', 'Décision inconnue.');
    }
    await _client
        .from('claims')
        .update({'status': status, 'resolved_by': _userId})
        .eq('id', claimId);
  }

  Future<void> validateAttendance(
    String attendanceId, {
    required String status,
  }) async {
    if (status != 'present' && status != 'absent') {
      throw ArgumentError.value(status, 'status', 'Décision inconnue.');
    }
    await _client
        .from('attendance_records')
        .update({'status': status, 'marked_by': _userId})
        .eq('id', attendanceId);
  }

  Future<Map<String, dynamic>> summarizeCourse(String sessionId) async {
    late final dynamic data;
    try {
      final response = await _client.functions.invoke(
        'summarize-course',
        body: {'sessionId': sessionId},
      );
      data = response.data;
    } catch (error) {
      throw StateError(_aiErrorMessage(error));
    }
    if (data is! Map) {
      throw StateError('Réponse du service IA invalide.');
    }
    final result = Map<String, dynamic>.from(data);
    final error = result['error'];
    if (error != null) throw StateError('$error');
    return result;
  }

  Future<void> attachCoursePdf(
    String sessionId, {
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!fileName.toLowerCase().endsWith('.pdf')) {
      throw ArgumentError.value(fileName, 'fileName', 'Seuls les PDF sont acceptés.');
    }
    final path = 'courses/$sessionId.pdf';
    await _client.storage.from('course_pdfs').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'application/pdf',
        upsert: true,
      ),
    );
    await _client
        .from('sessions')
        .update({'pdf_path': path})
        .eq('id', sessionId);
    await _client.from('course_summaries').delete().eq('session_id', sessionId);
  }

  Future<void> signOut() => _client.auth.signOut();
}
