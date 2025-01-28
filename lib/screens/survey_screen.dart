import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

class SurveyScreen extends StatefulWidget {
  final String userEmail;
  final String userName;
  final String customerNumber;

  const SurveyScreen({
    Key? key,
    required this.userEmail,
    required this.userName,
    required this.customerNumber,
  }) : super(key: key);

  @override
  _SurveyScreenState createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  int? _selectedRating;
  bool _isSending = false; // To avoid double submission

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/offline_ratings.json');
  }

  Future<void> _saveRatingOffline(Map<String, dynamic> ratingData) async {
    final file = await _localFile;
    bool fileExists = await file.exists();

    List<dynamic> existingData = [];
    if (fileExists) {
      try {
        String contents = await file.readAsString();
        if (contents.isNotEmpty) {
          existingData = jsonDecode(contents);
        }
      } catch (e) {
        print("Error decoding existing data: $e");
      }
    }

    existingData.add(ratingData);

    await file.writeAsString(jsonEncode(existingData));
    print('Rating saved offline: $ratingData');
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

  Future<bool> isOnline() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    return connectivityResult != ConnectivityResult.none;
  }

  int getRatingValue(int rating) {
    switch (rating) {
      case 5: return 2;  // Excellent
      case 4: return 1;  // Good
      case 3: return 0;  // Fair
      case 2: return -1; // Poor
      case 1: return -2; // Very Poor
      default: return 0;
    }
  }

  Future<void> _sendRating(int rating) async {
    if(_isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final numericRating = getRatingValue(rating);

      final formData = {
        'name': widget.userName,
        'email': widget.userEmail,
        'customerNumber': widget.customerNumber,
        'rating': numericRating.toString(), // Convert to string for form data
      };
      if (await isOnline()) {
        print('Sending rating data: $formData'); // Debug print
        final response = await http.post(
          Uri.parse('https://cleaning-app-sand.vercel.app/api/ratingflutter'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: formData, // Send as form data
        );

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/ratings',
                (route) => false,
            arguments: {
              'userEmail': widget.userEmail,
              'userName': widget.userName,
            },
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('There was an error, please try again later!')),
          );
        }
      } else {
        await _saveRatingOffline(formData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No internet connection, rating saved offline!')),

        );
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/ratings',
              (route) => false,
          arguments: {
            'userEmail': widget.userEmail,
            'userName': widget.userName,
          },
        );
      }
    } catch (e) {
      print('Error sending rating: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There was an error, please try again later!')),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }


  @override
  void initState() {
    super.initState();
    _sendOfflineRatings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF4CAF50),
                  Color(0xFF388E3C),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: SafeArea(
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Rate Our Service",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Image.asset(
                    'assets/logo.png',
                    width: 120,
                    height: 40,
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "How was our service today?",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildRatingButton(
                      label: "Excellent - ممتاز",
                      icon: Icons.thumb_up_outlined,
                      color: const Color(0xFF4CAF50),
                      rating: 5,
                    ),
                    _buildRatingButton(
                      label: "Good - جيد",
                      icon: Icons.sentiment_satisfied_outlined,
                      color: const Color(0xFF4CAF50),
                      rating: 4,
                    ),
                    _buildRatingButton(
                      label: "Fair - مقبول",
                      icon: Icons.sentiment_neutral_outlined,
                      color: const Color(0xFFFFB300),
                      rating: 3,
                    ),
                    _buildRatingButton(
                      label: "Poor - سيء",
                      icon: Icons.sentiment_dissatisfied_outlined,
                      color: const Color(0xFFFF7043),
                      rating: 2,
                    ),
                    _buildRatingButton(
                      label: "Very Poor - سيء جداً",
                      icon: Icons.thumb_down_outlined,
                      color: const Color(0xFFE53935),
                      rating: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingButton({
    required String label,
    required IconData icon,
    required Color color,
    required int rating,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedRating = rating;
            });
            _sendRating(rating);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF333333),
                  ),
                ),
                Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}