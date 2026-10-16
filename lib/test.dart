import 'package:flutter/material.dart';
import 'academic_service.dart';
import 'app_session.dart';
import 'leave_service.dart' show LeaveService;

class MarkTestScreen extends StatefulWidget {
  final SubjectInfo subject;

  const MarkTestScreen({Key? key, required this.subject}) : super(key: key);

  @override
  State<MarkTestScreen> createState() => _MarkTestScreenState();
}

class _MarkTestScreenState extends State<MarkTestScreen> {
  // --- BRANDING ---
  final Color kalgidharBlue = const Color(0xFF002046);
  final Color kalgidharTeal = const Color(0xFF00796B);

  // --- CONFIGURATION ---
  final int maxScore = 17;

  // Data Lists
  List<StudentModel> _allStudents = [];
  List<StudentModel> _filteredStudents = [];

  final TextEditingController _searchController = TextEditingController();
  bool _isUploading = false;
  bool _isLoading = true;
  bool _alreadyUploaded = false; // marks for this date were saved before
  String? _loadError;

  // Date of the Monday Test (defaults to the most recent Monday)
  late DateTime _testDate = _lastMonday(DateTime.now());

  static DateTime _lastMonday(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Dispose all student controllers to prevent memory leaks
    for (var student in _allStudents) {
      student.controller.dispose();
    }
    super.dispose();
  }

  // Loads the class list from Supabase, then any marks already saved
  Future<void> _loadStudents() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final list = await AcademicService.loadStudents(widget.subject.classId);
      if (!mounted) return;
      for (final old in _allStudents) {
        old.controller.dispose();
      }
      _allStudents = list
          .map((st) => StudentModel(
                id: st.id,
                name: st.name,
                roll: st.roll,
                marks: 0,
                controller: TextEditingController(text: ""),
              ))
          .toList();
      _filteredStudents = List.from(_allStudents);
      await _loadExistingMarks();
    } catch (e) {
      debugPrint('Load students error: $e');
      if (mounted) setState(() => _loadError = 'Could not load the student list. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadExistingMarks() async {
    try {
      final saved = await AcademicService.loadExistingTest(subjectId: widget.subject.id, date: _testDate);
      if (!mounted) return;
      setState(() {
        _alreadyUploaded = saved.isNotEmpty;
        for (final st in _allStudents) {
          final mark = saved[st.id];
          if (mark != null && !mark.absent && mark.marks != null) {
            st.marks = mark.marks!.round();
            st.controller.text = st.marks.toString();
          } else {
            st.marks = 0;
            st.controller.text = "";
          }
        }
      });
    } catch (e) {
      debugPrint('Load existing marks error: $e');
    }
  }

  Future<void> _pickTestDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _testDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Date of the Monday Test',
    );
    if (picked != null && picked != _testDate) {
      setState(() => _testDate = picked);
      _loadExistingMarks();
    }
  }

  // --- LOGIC ---
  void _filterStudents(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredStudents = List.from(_allStudents);
      } else {
        _filteredStudents = _allStudents
            .where((s) => s.name.toLowerCase().contains(query.toLowerCase()) ||
            s.roll.contains(query))
            .toList();
      }
    });
  }

  void _updateMarks(StudentModel student, String value) {
    // 1. Handle empty input
    if (value.isEmpty) {
      setState(() => student.marks = 0);
      return;
    }

    // 2. Parse input
    int? newMark = int.tryParse(value);

    if (newMark != null) {
      if (newMark > maxScore) {
        // Error: Value too high
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Marks cannot exceed 17"),
              backgroundColor: Colors.red,
              duration: Duration(milliseconds: 1000),
            )
        );
        // Reset to Max
        student.controller.text = maxScore.toString();
        student.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: student.controller.text.length));
        setState(() => student.marks = maxScore);
      } else {
        // Valid Mark
        setState(() => student.marks = newMark);
      }
    }
  }

  Color _getStatusColor(int marks) {
    double percentage = marks / maxScore;
    if (percentage < 0.35) return Colors.redAccent;
    if (percentage < 0.70) return Colors.orangeAccent;
    return Colors.green;
  }

  Future<void> _uploadData() async {
    FocusScope.of(context).unfocus(); // Hide keyboard
    final faculty = AppSession.currentUser;
    if (faculty == null || _allStudents.isEmpty) return;

    setState(() => _isUploading = true);

    // Empty box = absent. A typed 0 is saved as 0 marks.
    final marksByStudent = <String, double?>{
      for (final st in _allStudents)
        st.id: st.controller.text.trim().isEmpty ? null : st.marks.toDouble(),
    };

    try {
      await AcademicService.saveTest(
        subject: widget.subject,
        facultyId: faculty.id,
        date: _testDate,
        maxMarks: maxScore.toDouble(),
        marksByStudent: marksByStudent,
      );
    } catch (e) {
      debugPrint('Upload marks error: $e');
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not upload marks. Check your internet connection and try again."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isUploading = false);

    final filled = marksByStudent.values.where((m) => m != null).length;
    final absent = _allStudents.length - filled;

    showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text("Saved", style: TextStyle(color: kalgidharBlue, fontWeight: FontWeight.bold)),
          content: Text(
            "Monday Test of ${LeaveService.formatDate(_testDate)} saved.\n\n"
            "Marks: $filled students\nAbsent (empty box): $absent students",
          ),
          actions: [
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kalgidharBlue),
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back to dashboard
                },
                child: const Text("OK", style: TextStyle(color: Colors.white))
            )
          ],
        )
    );
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9), // Light background
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: kalgidharBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Column(
          children: [
            const Text("Monday Test", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
            Text(widget.subject.label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Header Info
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: Colors.white,
            width: double.infinity,
            child: Column(
              children: [
                Text(
                    "Max Score: $maxScore",
                    style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _isUploading ? null : _pickTestDate,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: kalgidharBlue.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kalgidharBlue.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month, size: 16, color: kalgidharBlue),
                        const SizedBox(width: 6),
                        Text("Test date: ${LeaveService.formatDate(_testDate)}",
                            style: TextStyle(color: kalgidharBlue, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 4),
                        Icon(Icons.edit, size: 14, color: kalgidharBlue),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _alreadyUploaded
                      ? "Marks for this date were uploaded before. Uploading again will update them."
                      : "Leave the box empty for absent students.",
                  style: TextStyle(fontSize: 11, color: _alreadyUploaded ? Colors.amber[900] : Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
                  ]
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filterStudents,
                decoration: const InputDecoration(
                    hintText: "Search Name or Roll No...",
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                    contentPadding: EdgeInsets.symmetric(vertical: 15)
                ),
              ),
            ),
          ),

          // Student List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                        TextButton.icon(onPressed: _loadStudents, icon: const Icon(Icons.refresh), label: const Text("Try again")),
                      ],
                    ),
                  )
                : _filteredStudents.isEmpty
                ? Center(
                    child: Text(
                      _allStudents.isEmpty ? "No students are in ${widget.subject.className} yet." : "No students found",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              itemCount: _filteredStudents.length,
              itemBuilder: (context, index) {
                final student = _filteredStudents[index];
                final double progress = student.marks / maxScore;

                return Container(
                  margin: const EdgeInsets.only(bottom: 15),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: kalgidharBlue.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 5))
                      ]
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                            child: Text(
                                student.name[0],
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kalgidharBlue)
                            )
                        ),
                      ),
                      const SizedBox(width: 15),

                      // Name Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(student.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kalgidharBlue)),
                            const SizedBox(height: 4),
                            Text(student.roll, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                          ],
                        ),
                      ),

                      // --- UNIQUE INPUT SECTION ---
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // 1. Ring
                          SizedBox(
                            width: 55, height: 55,
                            child: CircularProgressIndicator(
                              value: progress > 1.0 ? 1.0 : progress,
                              backgroundColor: Colors.grey[200],
                              color: _getStatusColor(student.marks),
                              strokeWidth: 5,
                            ),
                          ),
                          // 2. Input
                          SizedBox(
                            width: 35,
                            child: TextField(
                              controller: student.controller,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kalgidharBlue),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: "0",
                                isDense: true,
                              ),
                              onChanged: (val) => _updateMarks(student, val),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // Upload Button
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: ElevatedButton(
            onPressed: (_isUploading || _isLoading || _allStudents.isEmpty) ? null : _uploadData,
            style: ElevatedButton.styleFrom(
              backgroundColor: kalgidharBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              padding: const EdgeInsets.symmetric(vertical: 18),
              elevation: 5,
            ),
            child: _isUploading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_alreadyUploaded ? "UPDATE SCORES" : "UPLOAD SCORES", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2)),
          ),
        ),
      ),
    );
  }
}

// --- HELPER MODEL CLASS ---
class StudentModel {
  String id; // Supabase user id
  String name;
  String roll;
  int marks;
  TextEditingController controller;

  StudentModel({
    required this.id,
    required this.name,
    required this.roll,
    required this.marks,
    required this.controller
  });
}
