import 'dart:typed_data';

// The excel package has its own Border/BorderStyle classes that clash with
// Flutter's, so it is only used inside this file, with the "xl" prefix.
import 'package:excel/excel.dart' as xl;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'academic_service.dart';
import 'performance_service.dart';
import 'leave_service.dart' show LeaveService;

/// Result of making an Excel report.
class ExportResult {
  final bool saved;
  final bool noData;
  final String? location;

  const ExportResult._(this.saved, this.noData, this.location);

  static const ExportResult nothingToExport = ExportResult._(false, true, null);
  static const ExportResult cancelled = ExportResult._(false, false, null);
  factory ExportResult.savedTo(String location) => ExportResult._(true, false, location);
}

/// Builds real .xlsx files: an attendance register and a Monday Test report.
class ExcelExport {
  // --- Colors (ARGB) ---
  static final xl.ExcelColor _navy = xl.ExcelColor.fromHexString('FF002046');
  static final xl.ExcelColor _white = xl.ExcelColor.fromHexString('FFFFFFFF');
  static final xl.ExcelColor _greenText = xl.ExcelColor.fromHexString('FF1B5E20');
  static final xl.ExcelColor _greenFill = xl.ExcelColor.fromHexString('FFE8F5E9');
  static final xl.ExcelColor _redText = xl.ExcelColor.fromHexString('FFB71C1C');
  static final xl.ExcelColor _redFill = xl.ExcelColor.fromHexString('FFFFEBEE');
  static final xl.ExcelColor _orangeText = xl.ExcelColor.fromHexString('FFE65100');
  static final xl.ExcelColor _greyText = xl.ExcelColor.fromHexString('FF616161');
  static final xl.ExcelColor _greyFill = xl.ExcelColor.fromHexString('FFF5F5F5');

  static xl.Border get _thin =>
      xl.Border(borderStyle: xl.BorderStyle.Thin, borderColorHex: xl.ExcelColor.fromHexString('FFBDBDBD'));

  static xl.CellStyle _style({
    bool bold = false,
    int? fontSize,
    xl.ExcelColor? font,
    xl.ExcelColor? fill,
    bool center = false,
    bool border = true,
    bool wrap = false,
  }) {
    return xl.CellStyle(
      bold: bold,
      fontSize: fontSize,
      fontColorHex: font ?? xl.ExcelColor.black,
      backgroundColorHex: fill ?? xl.ExcelColor.none,
      horizontalAlign: center ? xl.HorizontalAlign.Center : xl.HorizontalAlign.Left,
      verticalAlign: xl.VerticalAlign.Center,
      textWrapping: wrap ? xl.TextWrapping.WrapText : null,
      leftBorder: border ? _thin : null,
      rightBorder: border ? _thin : null,
      topBorder: border ? _thin : null,
      bottomBorder: border ? _thin : null,
    );
  }

  static void _put(xl.Sheet sheet, int col, int row, Object? value, xl.CellStyle style) {
    xl.CellValue? cell;
    if (value == null) {
      cell = null;
    } else if (value is int) {
      cell = xl.IntCellValue(value);
    } else if (value is double) {
      cell = xl.DoubleCellValue(value);
    } else {
      cell = xl.TextCellValue(value.toString());
    }
    sheet.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row), cell, cellStyle: style);
  }

  /// Title rows at the top of a sheet. Returns the next free row.
  static int _writeTitle(xl.Sheet sheet, String title, List<String> lines) {
    _put(sheet, 0, 0, 'Akal University', _style(bold: true, fontSize: 16, font: _navy, border: false));
    _put(sheet, 0, 1, title, _style(bold: true, fontSize: 13, border: false));
    var row = 2;
    for (final line in lines) {
      _put(sheet, 0, row, line, _style(font: _greyText, border: false));
      row++;
    }
    return row + 1; // one empty row before the table
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  static String _safeName(String text) =>
      text.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'_+$'), '');

  static String _dateForFile(DateTime d) => LeaveService.toDbDate(d);

  // ------------------------------------------------------------------
  // ATTENDANCE REGISTER
  // ------------------------------------------------------------------

  static Future<ExportResult> attendanceReport({
    required SubjectInfo subject,
    required String facultyName,
  }) async {
    final register = await AcademicService.loadAttendanceRegister(subject);
    if (register.sessions.isEmpty || register.students.isEmpty) return ExportResult.nothingToExport;

    final excel = xl.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Attendance');
    final sheet = excel['Attendance'];

    final today = DateTime.now();
    var row = _writeTitle(sheet, 'Attendance Register', [
      'Class: ${subject.className}    Subject: ${subject.name} (${subject.code})',
      'Faculty: $facultyName    Lectures: ${register.sessions.length}    Generated: ${LeaveService.formatDate(today)}',
      'P = Present, A = Absent, - = not marked. Below 75% is highlighted in red.',
    ]);

    // Header row
    final header = _style(bold: true, font: _white, fill: _navy, center: true, wrap: true);
    final headerRow = row;
    _put(sheet, 0, row, 'S.No', header);
    _put(sheet, 1, row, 'Roll No', header);
    _put(sheet, 2, row, 'Student Name', header);
    var col = 3;
    for (final s in register.sessions) {
      final date = DateTime.tryParse(s['lecture_date'].toString());
      final label = date == null ? s['lecture_date'].toString() : '${date.day}/${date.month}/${date.year}';
      _put(sheet, col, row, '$label\n${AcademicService.shortSlot(s['time_slot'].toString())}', header);
      col++;
    }
    final presentCol = col;
    _put(sheet, presentCol, row, 'Present', header);
    _put(sheet, presentCol + 1, row, 'Total', header);
    _put(sheet, presentCol + 2, row, 'Attendance %', header);
    row++;

    // One row per student
    final below75 = <List<Object>>[];
    for (var i = 0; i < register.students.length; i++) {
      final st = register.students[i];
      final plain = _style(fill: i.isOdd ? _greyFill : null);
      final plainCenter = _style(fill: i.isOdd ? _greyFill : null, center: true);

      _put(sheet, 0, row, i + 1, plainCenter);
      _put(sheet, 1, row, st.roll, plainCenter);
      _put(sheet, 2, row, st.name, plain);

      var present = 0;
      var marked = 0;
      col = 3;
      for (final s in register.sessions) {
        final status = register.statusBySession[s['id'] as int]?[st.id];
        if (status == 'P') {
          present++;
          marked++;
          _put(sheet, col, row, 'P', _style(font: _greenText, fill: _greenFill, center: true, bold: true));
        } else if (status == 'A') {
          marked++;
          _put(sheet, col, row, 'A', _style(font: _redText, fill: _redFill, center: true, bold: true));
        } else {
          _put(sheet, col, row, '-', plainCenter);
        }
        col++;
      }

      final pct = marked == 0 ? 0.0 : _round1(present * 100 / marked);
      final low = marked > 0 && pct < 75;
      _put(sheet, presentCol, row, present, plainCenter);
      _put(sheet, presentCol + 1, row, marked, plainCenter);
      _put(sheet, presentCol + 2, row, pct,
          low ? _style(font: _redText, fill: _redFill, center: true, bold: true) : _style(font: _greenText, center: true, bold: true));
      if (low) below75.add([st.roll, st.name, present, marked, pct]);
      row++;
    }

    // Column widths
    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 11);
    sheet.setColumnWidth(2, 24);
    for (var c = 3; c < presentCol; c++) {
      sheet.setColumnWidth(c, 11);
    }
    sheet.setColumnWidth(presentCol, 9);
    sheet.setColumnWidth(presentCol + 1, 8);
    sheet.setColumnWidth(presentCol + 2, 13);
    sheet.setRowHeight(headerRow, 32);

    // Second sheet: students below 75%
    final lowSheet = excel['Below 75%'];
    var r = _writeTitle(lowSheet, 'Students Below 75% Attendance', [
      'Class: ${subject.className}    Subject: ${subject.name} (${subject.code})',
    ]);
    if (below75.isEmpty) {
      _put(lowSheet, 0, r, 'All students have 75% or more attendance.', _style(font: _greenText, bold: true, border: false));
    } else {
      final h = ['Roll No', 'Student Name', 'Present', 'Total', 'Attendance %'];
      for (var c = 0; c < h.length; c++) {
        _put(lowSheet, c, r, h[c], header);
      }
      r++;
      for (final item in below75) {
        for (var c = 0; c < item.length; c++) {
          _put(lowSheet, c, r, item[c],
              c == 4 ? _style(font: _redText, fill: _redFill, center: true, bold: true) : _style(center: c != 1));
        }
        r++;
      }
    }
    lowSheet.setColumnWidth(0, 11);
    lowSheet.setColumnWidth(1, 24);
    lowSheet.setColumnWidth(2, 9);
    lowSheet.setColumnWidth(3, 8);
    lowSheet.setColumnWidth(4, 13);

    excel.setDefaultSheet('Attendance');
    final fileName = 'Attendance_${_safeName(subject.className)}_${_safeName(subject.name)}_${_dateForFile(today)}';
    return _save(excel, fileName);
  }

  // ------------------------------------------------------------------
  // MONDAY TEST REPORT
  // ------------------------------------------------------------------

  static Future<ExportResult> mondayTestReport({
    required SubjectInfo subject,
    required String facultyName,
  }) async {
    final register = await AcademicService.loadTestRegister(subject);
    if (register.tests.isEmpty || register.students.isEmpty) return ExportResult.nothingToExport;

    final excel = xl.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Monday Tests');
    final sheet = excel['Monday Tests'];

    final today = DateTime.now();
    final maxMarks = (register.tests.first['max_marks'] as num?)?.toDouble() ?? 17.0;
    var row = _writeTitle(sheet, 'Monday Test Report', [
      'Class: ${subject.className}    Subject: ${subject.name} (${subject.code})',
      'Faculty: $facultyName    Tests: ${register.tests.length}    Max marks per test: ${_fmt(maxMarks)}    Generated: ${LeaveService.formatDate(today)}',
      'AB = Absent, - = not entered. Red = below 35%, orange = below 70%.',
    ]);

    final header = _style(bold: true, font: _white, fill: _navy, center: true, wrap: true);
    final headerRow = row;
    _put(sheet, 0, row, 'S.No', header);
    _put(sheet, 1, row, 'Roll No', header);
    _put(sheet, 2, row, 'Student Name', header);
    var col = 3;
    for (final t in register.tests) {
      final date = DateTime.tryParse(t['test_date'].toString());
      final label = date == null ? t['test_date'].toString() : '${date.day}/${date.month}/${date.year}';
      _put(sheet, col, row, '$label\n(/${_fmt((t['max_marks'] as num?)?.toDouble() ?? 17)})', header);
      col++;
    }
    final summaryCol = col;
    _put(sheet, summaryCol, row, 'Tests Taken', header);
    _put(sheet, summaryCol + 1, row, 'Average', header);
    _put(sheet, summaryCol + 2, row, 'Average %', header);
    row++;

    final testTotals = List<double>.filled(register.tests.length, 0);
    final testCounts = List<int>.filled(register.tests.length, 0);

    for (var i = 0; i < register.students.length; i++) {
      final st = register.students[i];
      final plain = _style(fill: i.isOdd ? _greyFill : null);
      final plainCenter = _style(fill: i.isOdd ? _greyFill : null, center: true);

      _put(sheet, 0, row, i + 1, plainCenter);
      _put(sheet, 1, row, st.roll, plainCenter);
      _put(sheet, 2, row, st.name, plain);

      var sum = 0.0;
      var taken = 0;
      var pctSum = 0.0;
      col = 3;
      for (var t = 0; t < register.tests.length; t++) {
        final test = register.tests[t];
        final max = (test['max_marks'] as num?)?.toDouble() ?? 17.0;
        final mark = register.marksByTest[test['id'] as int]?[st.id];
        if (mark == null) {
          _put(sheet, col, row, '-', plainCenter);
        } else if (mark.absent || mark.marks == null) {
          _put(sheet, col, row, 'AB', _style(font: _redText, center: true, bold: true, fill: i.isOdd ? _greyFill : null));
        } else {
          final m = mark.marks!;
          sum += m;
          taken++;
          pctSum += max == 0 ? 0 : m / max;
          testTotals[t] += m;
          testCounts[t]++;
          _put(sheet, col, row, m, _style(font: _scoreColor(m, max), center: true, bold: true, fill: i.isOdd ? _greyFill : null));
        }
        col++;
      }

      final avg = taken == 0 ? 0.0 : _round1(sum / taken);
      final avgPct = taken == 0 ? 0.0 : _round1(pctSum * 100 / taken);
      _put(sheet, summaryCol, row, taken, plainCenter);
      _put(sheet, summaryCol + 1, row, avg, _style(center: true, bold: true, font: taken == 0 ? null : _scoreColor(avgPct, 100)));
      _put(sheet, summaryCol + 2, row, avgPct, _style(center: true, bold: true, font: taken == 0 ? null : _scoreColor(avgPct, 100)));
      row++;
    }

    // Class average for each test
    final footer = _style(bold: true, fill: _greyFill, center: true);
    _put(sheet, 0, row, '', footer);
    _put(sheet, 1, row, '', footer);
    _put(sheet, 2, row, 'Class Average', _style(bold: true, fill: _greyFill));
    for (var t = 0; t < register.tests.length; t++) {
      _put(sheet, 3 + t, row, testCounts[t] == 0 ? '-' : _round1(testTotals[t] / testCounts[t]), footer);
    }
    _put(sheet, summaryCol, row, '', footer);
    _put(sheet, summaryCol + 1, row, '', footer);
    _put(sheet, summaryCol + 2, row, '', footer);

    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 11);
    sheet.setColumnWidth(2, 24);
    for (var c = 3; c < summaryCol; c++) {
      sheet.setColumnWidth(c, 11);
    }
    sheet.setColumnWidth(summaryCol, 11);
    sheet.setColumnWidth(summaryCol + 1, 10);
    sheet.setColumnWidth(summaryCol + 2, 11);
    sheet.setRowHeight(headerRow, 32);

    excel.setDefaultSheet('Monday Tests');
    final fileName = 'Monday_Test_${_safeName(subject.className)}_${_safeName(subject.name)}_${_dateForFile(today)}';
    return _save(excel, fileName);
  }

  static xl.ExcelColor _scoreColor(double value, double max) {
    final pct = max == 0 ? 0 : value / max;
    if (pct < 0.35) return _redText;
    if (pct < 0.70) return _orangeText;
    return _greenText;
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ------------------------------------------------------------------
  // WHOLE-CLASS PERFORMANCE (admin / HOD)
  // Sheet 1: every student, attendance % and Monday Test % per subject
  // Sheet 2: every subject, teacher, lectures, class averages
  // ------------------------------------------------------------------

  static Future<ExportResult> classPerformanceReport(ClassDetail detail) async {
    if (detail.students.isEmpty) return ExportResult.nothingToExport;

    final excel = xl.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Students');
    final sheet = excel['Students'];
    final summary = detail.summary;
    final today = DateTime.now();
    final subjects = detail.subjects;

    String pctText(double? v) => v == null ? '-' : '${_round1(v)}%';

    var row = _writeTitle(sheet, 'Class Performance Report', [
      'Class: ${summary.className}    Department: ${summary.departmentName}    Class in-charge: ${summary.classTeacherName ?? '-'}',
      'Students: ${summary.students}    Lectures: ${summary.lectures}    Monday Tests: ${summary.tests}    Generated: ${LeaveService.formatDate(today)}',
      'Class attendance: ${pctText(summary.attendancePct)}    Class Monday Test average: ${pctText(summary.testPct)}',
      'Red = attendance below 75% or marks below 35%. Orange = marks below 70%. - = no data yet.',
    ]);

    final header = _style(bold: true, font: _white, fill: _navy, center: true, wrap: true);
    final headerRow = row;
    _put(sheet, 0, row, 'S.No', header);
    _put(sheet, 1, row, 'Roll No', header);
    _put(sheet, 2, row, 'Student Name', header);
    var col = 3;
    for (final s in subjects) {
      _put(sheet, col++, row, '${s.code}\nAtt %', header);
    }
    final overallAttCol = col;
    _put(sheet, col++, row, 'Overall\nAtt %', header);
    final firstTestCol = col;
    for (final s in subjects) {
      _put(sheet, col++, row, '${s.code}\nTest %', header);
    }
    final overallTestCol = col;
    _put(sheet, col++, row, 'Overall\nTest %', header);
    final remarksCol = col;
    _put(sheet, remarksCol, row, 'Remarks', header);
    row++;

    final students = [...detail.students]..sort((a, b) => a.roll.compareTo(b.roll));
    for (var i = 0; i < students.length; i++) {
      final st = students[i];
      final fill = i.isOdd ? _greyFill : null;
      final plain = _style(fill: fill);
      final plainCenter = _style(fill: fill, center: true);

      _put(sheet, 0, row, i + 1, plainCenter);
      _put(sheet, 1, row, st.roll, plainCenter);
      _put(sheet, 2, row, st.name, plain);

      col = 3;
      for (final s in subjects) {
        final pct = st.bySubject[s.subjectId]?.attendancePct;
        _put(sheet, col++, row, pct == null ? '-' : _round1(pct), _attStyle(pct, fill));
      }
      _put(sheet, overallAttCol, row, st.attendancePct == null ? '-' : _round1(st.attendancePct!),
          _attStyle(st.attendancePct, fill, bold: true));

      col = firstTestCol;
      for (final s in subjects) {
        final pct = st.bySubject[s.subjectId]?.testPct;
        _put(sheet, col++, row, pct == null ? '-' : _round1(pct), _testStyle(pct, fill));
      }
      _put(sheet, overallTestCol, row, st.testPct == null ? '-' : _round1(st.testPct!),
          _testStyle(st.testPct, fill, bold: true));

      final remarks = <String>[
        if (st.lowAttendance) 'Low attendance',
        if (st.lowMarks) 'Low marks',
        if (st.testsAbsent > 0) 'Absent in ${st.testsAbsent} test${st.testsAbsent == 1 ? '' : 's'}',
      ];
      _put(sheet, remarksCol, row, remarks.isEmpty ? 'OK' : remarks.join(', '),
          remarks.isEmpty ? _style(fill: fill, font: _greenText) : _style(fill: fill, font: _redText, bold: true));
      row++;
    }

    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 11);
    sheet.setColumnWidth(2, 24);
    for (var c = 3; c < remarksCol; c++) {
      sheet.setColumnWidth(c, 10);
    }
    sheet.setColumnWidth(remarksCol, 30);
    sheet.setRowHeight(headerRow, 32);

    // Sheet 2: subjects
    final subSheet = excel['Subjects'];
    var r = _writeTitle(subSheet, 'Subject Summary - ${summary.className}', [
      'Class averages for each subject.',
    ]);
    final h = ['Subject', 'Code', 'Teacher', 'Lectures', 'Class Att %', 'Monday Tests', 'Class Test Avg %'];
    for (var c = 0; c < h.length; c++) {
      _put(subSheet, c, r, h[c], header);
    }
    subSheet.setRowHeight(r, 28);
    r++;
    for (var i = 0; i < subjects.length; i++) {
      final s = subjects[i];
      final fill = i.isOdd ? _greyFill : null;
      _put(subSheet, 0, r, s.name, _style(fill: fill, bold: true));
      _put(subSheet, 1, r, s.code, _style(fill: fill, center: true));
      _put(subSheet, 2, r, s.teacherName ?? 'Not assigned', _style(fill: fill));
      _put(subSheet, 3, r, s.lectures, _style(fill: fill, center: true));
      _put(subSheet, 4, r, s.attendancePct == null ? '-' : _round1(s.attendancePct!), _attStyle(s.attendancePct, fill));
      _put(subSheet, 5, r, s.tests, _style(fill: fill, center: true));
      _put(subSheet, 6, r, s.testPct == null ? '-' : _round1(s.testPct!), _testStyle(s.testPct, fill));
      r++;
    }
    subSheet.setColumnWidth(0, 24);
    subSheet.setColumnWidth(1, 10);
    subSheet.setColumnWidth(2, 20);
    subSheet.setColumnWidth(3, 10);
    subSheet.setColumnWidth(4, 12);
    subSheet.setColumnWidth(5, 13);
    subSheet.setColumnWidth(6, 16);

    excel.setDefaultSheet('Students');
    final fileName = 'Class_Performance_${_safeName(summary.className)}_${_dateForFile(today)}';
    return _save(excel, fileName);
  }

  static xl.CellStyle _attStyle(double? pct, xl.ExcelColor? fill, {bool bold = false}) {
    if (pct == null) return _style(fill: fill, center: true, font: _greyText);
    if (pct < 75) return _style(fill: _redFill, center: true, font: _redText, bold: true);
    return _style(fill: fill, center: true, font: _greenText, bold: bold);
  }

  static xl.CellStyle _testStyle(double? pct, xl.ExcelColor? fill, {bool bold = false}) {
    if (pct == null) return _style(fill: fill, center: true, font: _greyText);
    return _style(fill: pct < 35 ? _redFill : fill, center: true, font: _scoreColor(pct, 100), bold: bold || pct < 35);
  }

  // ------------------------------------------------------------------
  // SAVING
  // Web (Chrome): downloads straight to the Downloads folder.
  // Android / desktop: opens a "Save as" screen so you choose where.
  // ------------------------------------------------------------------

  static Future<ExportResult> _save(xl.Excel excel, String fileName) async {
    final encoded = excel.encode();
    if (encoded == null) throw Exception('Could not create the Excel file.');
    final bytes = Uint8List.fromList(encoded);

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      return ExportResult.savedTo('your Downloads folder');
    }

    final path = await FileSaver.instance.saveAs(
      name: fileName,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
    if (path == null || path.isEmpty) return ExportResult.cancelled;
    return ExportResult.savedTo(path);
  }
}
