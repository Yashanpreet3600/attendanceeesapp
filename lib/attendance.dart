import 'package:flutter/material.dart';
import 'academic_service.dart';
import 'app_session.dart';

class MarkAttendanceScreen extends StatefulWidget {
  final SubjectInfo subject;

  const MarkAttendanceScreen({super.key, required this.subject});

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  // --- BRANDING ---
  final Color kalgidharBlue = const Color(0xFF002046);

  // --- STATE VARIABLES ---
  DateTime selectedDate = DateTime.now();
  String selectedTimeSlot = ""; // Holds the selected string from the list
  List<String> timeSlots = []; // Generated list

  // Students of this class (loaded from Supabase). Everyone starts as Present.
  List<Map<String, dynamic>> students = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _alreadySubmitted = false; // this lecture was marked before
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _generateTimeSlots();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final list = await AcademicService.loadStudents(widget.subject.classId);
      if (!mounted) return;
      students = list
          .map((s) => <String, dynamic>{'id': s.id, 'name': s.name, 'roll': s.roll, 'status': 'P'})
          .toList();
      await _loadExisting();
    } catch (e) {
      debugPrint('Load students error: $e');
      if (mounted) setState(() => _loadError = 'Could not load the student list. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // If this date + lecture was already submitted, show what was saved
  Future<void> _loadExisting() async {
    try {
      final saved = await AcademicService.loadExistingAttendance(
        subjectId: widget.subject.id,
        date: selectedDate,
        timeSlot: selectedTimeSlot,
      );
      if (!mounted) return;
      setState(() {
        _alreadySubmitted = saved.isNotEmpty;
        for (final s in students) {
          s['status'] = saved[s['id']] ?? 'P';
        }
      });
    } catch (e) {
      debugPrint('Load existing attendance error: $e');
    }
  }

  // --- LOGIC: GENERATE 9 SLOTS, 50 MIN GAP, START 9:00 ---
  void _generateTimeSlots() {
    timeSlots.clear();
    DateTime startTime = DateTime(2024, 1, 1, 9, 0); // Start at 9:00 AM

    for (int i = 0; i < 9; i++) {
      DateTime endTime = startTime.add(const Duration(minutes: 50));

      // Formatting time manually to avoid external dependencies like intl
      String startStr = "${_formatTime(startTime.hour)}:${_formatTime(startTime.minute)}";
      String endStr = "${_formatTime(endTime.hour)}:${_formatTime(endTime.minute)}";

      timeSlots.add("L${i + 1}: $startStr - $endStr");

      // The next class starts immediately after the previous one?
      // Or usually there is a break? Assuming continuous based on prompt.
      startTime = endTime;
    }
    // Set default to 1st slot
    selectedTimeSlot = timeSlots[0];
  }

  String _formatTime(int time) {
    return time.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    // Calculate Summary
    int totalPresent = students.where((s) => s['status'] == 'P').length;
    int totalAbsent = students.length - totalPresent;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: kalgidharBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Mark Attendance", style: TextStyle(color: Colors.white, fontSize: 18)),
            Text(widget.subject.label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle),
            tooltip: "Submit",
            onPressed: (_isLoading || _isSaving || students.isEmpty) ? null : () => _submitAttendance(),
          )
        ],
      ),
      body: Column(
        children: [
          // --- TOP CONTROL BAR (Date & Time) ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: Column(
              children: [
                // ROW 1: Date & Time Selectors
                Row(
                  children: [
                    // --- 1. DATE SELECTOR (MANUAL) ---
                    Expanded(
                      flex: 4,
                      child: InkWell(
                        onTap: () => _selectDate(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300)
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month, size: 18, color: kalgidharBlue),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Date", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  Text(
                                    "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey[800]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // --- 2. TIME SLOT SELECTOR (DROPDOWN) ---
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                            color: kalgidharBlue.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: kalgidharBlue.withOpacity(0.3))
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedTimeSlot,
                            isExpanded: true,
                            icon: Icon(Icons.arrow_drop_down, color: kalgidharBlue),
                            style: TextStyle(color: kalgidharBlue, fontWeight: FontWeight.bold, fontSize: 13),
                            onChanged: (String? newValue) {
                              setState(() {
                                selectedTimeSlot = newValue!;
                              });
                              _loadExisting();
                            },
                            items: timeSlots.map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ROW 2: Mark All Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Mark All Present", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: totalPresent == students.length,
                        activeColor: kalgidharBlue,
                        onChanged: (val) {
                          setState(() {
                            for (var s in students) {
                              s['status'] = val ? 'P' : 'A';
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // --- ALREADY SUBMITTED BANNER ---
          if (_alreadySubmitted)
            Container(
              width: double.infinity,
              color: Colors.amber[50],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber[900], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Attendance for this lecture was already submitted. Submitting again will update it.",
                      style: TextStyle(color: Colors.amber[900], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // --- STUDENT LIST ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 10),
                          TextButton.icon(onPressed: _loadStudents, icon: const Icon(Icons.refresh), label: const Text("Try again")),
                        ],
                      ),
                    ),
                  )
                : students.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        "No students are in ${widget.subject.className} yet. Ask the admin to add them in Supabase (app_users table).",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
              itemCount: students.length,
              padding: const EdgeInsets.only(bottom: 80, top: 10),
              itemBuilder: (context, index) {
                final student = students[index];
                bool isPresent = student['status'] == 'P';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.shade200)
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    leading: CircleAvatar(
                      backgroundColor: isPresent ? kalgidharBlue : Colors.red,
                      child: Text(
                        student['name'][0],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(student['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Roll No: ${student['roll']}"),
                    trailing: InkWell(
                      onTap: () {
                        setState(() {
                          student['status'] = isPresent ? 'A' : 'P';
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 90,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                            color: isPresent ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isPresent ? Colors.green : Colors.red)
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          isPresent ? "Present" : "Absent",
                          style: TextStyle(
                              color: isPresent ? Colors.green[700] : Colors.red[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 12
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // --- BOTTOM SUMMARY BAR ---
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Total Students: ${students.length}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                Row(
                  children: [
                    Text("P: $totalPresent", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 15),
                    Text("A: $totalAbsent", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                )
              ],
            ),
            ElevatedButton(
              onPressed: (_isLoading || _isSaving || students.isEmpty) ? null : () => _submitAttendance(),
              style: ElevatedButton.styleFrom(
                backgroundColor: kalgidharBlue,
                disabledBackgroundColor: kalgidharBlue.withOpacity(0.4),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_alreadySubmitted ? "UPDATE" : "SUBMIT", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  // --- HELPER FUNCTIONS ---

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(), // attendance can't be marked for future dates
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: kalgidharBlue),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      _loadExisting();
    }
  }

  void _submitAttendance() {
    int p = students.where((s) => s['status'] == 'P').length;
    int a = students.length - p;
    String dateStr = "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("Confirm Submission", style: TextStyle(color: kalgidharBlue)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Class: ${widget.subject.label}", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text("Date: $dateStr"),
            Text("Slot: $selectedTimeSlot"),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 5),
                Text("Present: $p"),
                const SizedBox(width: 20),
                const Icon(Icons.cancel, color: Colors.red, size: 16),
                const SizedBox(width: 5),
                Text("Absent: $a"),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Edit")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kalgidharBlue),
            onPressed: () {
              Navigator.pop(ctx);
              _saveAttendance();
            },
            child: const Text("Confirm", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Saves to Supabase, then goes back to the dashboard
  Future<void> _saveAttendance() async {
    final faculty = AppSession.currentUser;
    if (faculty == null) return;

    setState(() => _isSaving = true);
    try {
      await AcademicService.saveAttendance(
        subject: widget.subject,
        facultyId: faculty.id,
        date: selectedDate,
        timeSlot: selectedTimeSlot,
        statusByStudent: {for (final s in students) s['id'] as String: s['status'] as String},
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_alreadySubmitted ? "Attendance updated." : "Attendance submitted."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Save attendance error: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not save attendance. Check your internet connection and try again."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
