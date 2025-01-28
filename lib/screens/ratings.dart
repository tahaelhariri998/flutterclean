import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cleaning_app/main.dart';
import 'package:cleaning_app/screens/survey_screen.dart'; // استيراد صفحة التقييم
import 'package:path_provider/path_provider.dart';

class Rating {
  final int id;
  final String name;
  final String email;
  final String customerNumber;
  final int rating;
  final DateTime createdAt;

  Rating({
    required this.id,
    required this.name,
    required this.email,
    required this.customerNumber,
    required this.rating,
    required this.createdAt,
  });

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      customerNumber: json['customerNumber'],
      rating: json['rating'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class RatingsScreen extends StatefulWidget {
  final String userEmail;
  final String userName;

  const RatingsScreen({
    Key? key,
    required this.userEmail,
    required this.userName,
  }) : super(key: key);

  @override
  _RatingsScreenState createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  final TextEditingController _customerNumberController = TextEditingController();
  List<Rating> _ratings = [];
  Timer? _timer;
  bool _isOnline = true;
  bool _isLoading = true; // حالة التحميل الأولية
  bool _hasError = false; // حالة وجود خطأ في التحميل

  @override
  void initState() {
    super.initState();
    _startPeriodicFetch();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _customerNumberController.dispose();
    super.dispose();
  }

  void _startPeriodicFetch() {
    _fetchRatings(); // Initial fetch
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkConnectivityAndFetch();
    });
  }

  Future<void> _checkConnectivityAndFetch() async {
    bool newIsOnline = false; // Default to offline in case of exceptions
    try {
      final result = await http.get(Uri.parse('https://cleaning-app-sand.vercel.app/api/rating?email=${widget.userEmail}'));
      newIsOnline = result.statusCode == 200;

    } catch (e) {
      newIsOnline = false;
      print('Connectivity check error: $e');
    }

    if (newIsOnline != _isOnline) {
      setState(() {
        _isOnline = newIsOnline;
      });
      if (_isOnline) {
        await _sendOfflineRatings(); // Wait until this function completes
        await _fetchRatings();       // Wait until this function completes
      }
    }
  }
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/offline_ratings.json');
  }
  Future<bool> isOnline() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    return connectivityResult != ConnectivityResult.none;
  }
  Future<void> _sendOfflineRatings() async {
    if (!await isOnline()) {
      print("Offline, not sending ratings");
      return;
    }
    final file = await _localFile;
    bool fileExists = await file.exists();
    if (!fileExists) {
      print("No offline ratings to send");
      return;
    }

    try {
      String contents = await file.readAsString();
      if (contents.isEmpty){
        print("File is empty, no ratings to send");
        return;
      }

      List<dynamic> ratings = jsonDecode(contents);

      for (var ratingData in ratings) {
        await _sendRatingToServer(ratingData);
      }
      // Clear the file after successful sending
      await file.writeAsString('');

    } catch (e) {
      print("Error processing offline ratings: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There was an error sending offline ratings!')),
      );
    }
  }


  Future<void> _sendRatingToServer(Map<String, dynamic> ratingData) async {
    if (!await isOnline()) {
      return;
    }

    try{
      final response = await http.post(
        Uri.parse('https://cleaning-app-sand.vercel.app/api/ratingflutter'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: ratingData, // Send as form data
      );
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        print("Rating sent Successfully from the offline queue");
      } else {
        print("Failed to send from the offline queue ");
      }
    }
    catch (e){
      print('Error sending rating from offline : $e');
    }
  }

  Future<void> _fetchRatings() async {
    setState(() {
      _isLoading = true; // نبدأ التحميل
      _hasError = false; // نعيد تعيين حالة الخطأ
    });
    try {
      final response = await http.get(
        Uri.parse('https://cleaning-app-sand.vercel.app/api/rating?email=${widget.userEmail}'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _ratings = data.map((json) => Rating.fromJson(json)).toList();
          _isLoading = false; // تم التحميل بنجاح
        });
      } else {
        setState(() {
          _isLoading = false;
          _hasError = true; // كان هناك خطأ في التحميل
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true; // كان هناك خطأ في التحميل
      });
      print('Error fetching ratings: $e');
    }
  }

  int _calculateWeeklyTotal() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    return _ratings
        .where((rating) => rating.createdAt.isAfter(startOfWeek) &&
        rating.createdAt.isBefore(endOfWeek.add(const Duration(days: 1))))
        .fold(0, (sum, rating) => sum + rating.rating);
  }

  int _calculateMonthlyTotal() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    return _ratings
        .where((rating) => rating.createdAt.isAfter(startOfMonth) &&
        rating.createdAt.isBefore(endOfMonth.add(const Duration(days: 1))))
        .fold(0, (sum, rating) => sum + rating.rating);
  }

  int _calculateAllTimeTotal() {
    return _ratings.fold(0, (sum, rating) => sum + rating.rating);
  }

  void _navigateToSurvey() {
    if (_customerNumberController.text.length > 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SurveyScreen(
            userEmail: widget.userEmail,
            userName: widget.userName,
            customerNumber: _customerNumberController.text,
          ),
        ),
      );
    }
  }


  void _signOut() async {
    // Handle sign out
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clear shared preferences

    // Navigate to the main page (assuming your main page is the initial route)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MyApp()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Section
            Container(
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.green.shade400, Colors.green.shade700],
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/logo.png',
                      width: 250,
                      height: 100,
                    ),

                    const SizedBox(height: 16),
                    Icon(Icons.account_circle, size: 80, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(
                      widget.userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.userEmail,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

            // Customer Number Input
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _customerNumberController,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: 'enter customer number',
                      border: const UnderlineInputBorder(),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.purple.shade700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _navigateToSurvey,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade700,
                      ),
                      child: const Text(
                        'proceed to rating',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Ratings Table
            Container(
              height: 200,
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(1.5),
                    2: FlexColumnWidth(1),
                  },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Colors.white),
                      children: [
                        _buildTableHeader('rating'),
                        _buildTableHeader('customer number'),
                        _buildTableHeader('date'),
                      ],
                    ),
                    if (_isLoading) // عرض مؤشر التحميل اذا كان يتم تحميل البيانات
                      TableRow(
                        decoration: const BoxDecoration(color: Colors.white),
                        children: [
                          _buildTableCell(''),
                          _buildTableCell('Loading...'),
                          _buildTableCell(''),
                        ],
                      ),
                    if (!_isOnline && !_isLoading && _ratings.isEmpty && !_hasError) // عرض رسالة عدم الاتصال فقط في حالة عدم وجود بيانات و عدم وجود خطأ
                      TableRow(
                        decoration: const BoxDecoration(color: Colors.white),
                        children: [
                          _buildTableCell(''),
                          _buildTableCell('You are Offline'),
                          _buildTableCell(''),
                        ],
                      ),
                    if (!_isLoading && _hasError) // عرض رسالة خطأ في حالة وجود خطأ
                      TableRow(
                        decoration: const BoxDecoration(color: Colors.white),
                        children: [
                          _buildTableCell(''),
                          _buildTableCell('Error Loading Data'),
                          _buildTableCell(''),
                        ],
                      ),
                    ..._ratings.map((rating) => TableRow(
                      decoration: const BoxDecoration(color: Colors.white),
                      children: [
                        _buildTableCell(rating.rating.toString()),
                        _buildTableCell(rating.customerNumber),
                        _buildTableCell(DateFormat('yyyy-MM-dd').format(rating.createdAt)),
                      ],
                    )).toList(),
                  ],
                ),
              ),
            ),

            // Summary Statistics
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryCard('weekly total', _calculateWeeklyTotal().toString()),
                  _buildSummaryCard('monthly total', _calculateMonthlyTotal().toString()),
                  _buildSummaryCard('all time total', _calculateAllTimeTotal().toString()),
                ],
              ),
            ),

            // Sign Out Button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _signOut,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: const Text(
                    'sign out',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.purple.shade700,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: Colors.purple.shade700,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

