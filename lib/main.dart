import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'screens/ratings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedEmail = prefs.getString('user_email');
  String? savedName = prefs.getString('user_full_name');

  runApp(MyApp(initialEmail: savedEmail, initialName: savedName));
}

class MyApp extends StatelessWidget {
  final String? initialEmail;
  final String? initialName;

  const MyApp({Key? key, this.initialEmail, this.initialName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: initialEmail != null
          ? AutoLoginCheck(email: initialEmail!, userName: initialName)
          : const EmailPage(),
    );
  }
}

class AutoLoginCheck extends StatefulWidget {
  final String email;
  final String? userName;

  const AutoLoginCheck({Key? key, required this.email, this.userName}) : super(key: key);

  @override
  _AutoLoginCheckState createState() => _AutoLoginCheckState();
}

class _AutoLoginCheckState extends State<AutoLoginCheck> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      // No internet, directly navigate to profile page with saved data if available
      _navigateToProfilePage();
      return;
    }

    // If internet, proceed with fetching user details from the server
    var user = await fetchUser(widget.email);
    if (user == null) {
      // User not found or some error - go to email page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const EmailPage()),
      );
    } else {
      // User is valid and we can navigate
      _navigateToProfilePage();
    }
  }

  void _navigateToProfilePage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ProfilePage(email: widget.email, userName: widget.userName ?? '')),
    );
  }

  Future<Map<String, dynamic>?> fetchUser(String email) async {
    final String apiUrl = "https://cleaning-app-sand.vercel.app/api/user?email=$email";
    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to fetch user');
      }
    } catch (e) {
      print('Error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}


class EmailPage extends StatefulWidget {
  const EmailPage({Key? key}) : super(key: key);

  @override
  _EmailPageState createState() => _EmailPageState();
}

class _EmailPageState extends State<EmailPage> {
  final TextEditingController emailController = TextEditingController();
  bool _isLoading = false;

  Future<Map<String, dynamic>?> fetchUser(String email) async {
    final String apiUrl =
        "https://cleaning-app-sand.vercel.app/api/user?email=$email";

    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No internet connection.')),
      );
      return null;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
      );
      setState(() {
        _isLoading = false;
      });
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to fetch user');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error: $e');
      return null;
    }
  }

  Future<void> handleUserFlow(BuildContext context, String email) async {
    var user = await fetchUser(email);
    if (user == null) {
      // User not found, create new user with push
      _navigateToNewPasswordPage(context, email, isNewUser: true);
    } else if (user['image'] == null) {
      // User exists, but password is null, update password with put
      _navigateToNewPasswordPage(context, email, isNewUser: false);
    } else {
      // User exists and has a password, verify it
      _navigateToVerifyPasswordPage(context, email, user['image']);
    }
  }

  void _navigateToNewPasswordPage(BuildContext context, String email,
      {required bool isNewUser}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewPasswordPage(
          email: email,
          isNewUser: isNewUser,
          onPasswordSet: (ctx) async {  // Add a BuildContext parameter here
            var updatedUser = await fetchUser(email);
            _handleUserAfterPasswordSet(context, updatedUser, email);
          },
        ),
      ),
    );
  }

  void _navigateToVerifyPasswordPage(
      BuildContext context, String email, String storedPassword) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerifyPasswordPage(
          email: email,
          storedPassword: storedPassword,
          onPasswordVerified: () async {
            var user = await fetchUser(email);
            _handleUserAfterPasswordSet(context, user, email);
          },
        ),
      ),
    );
  }

  void _handleUserAfterPasswordSet(
      BuildContext context, Map<String, dynamic>? updatedUser, String email) async {
    if (updatedUser != null &&
        (updatedUser['name'] == null || (updatedUser['name'] as String).isEmpty)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UpdateNamePage(email: email),
        ),
      );
    } else {
      // Save user login
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('user_email', email);
      prefs.setString('user_full_name', updatedUser?['name']);


      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login successful!')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => ProfilePage(email: email, userName: updatedUser?['name'] ?? '',)),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Email')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                    String email = emailController.text.trim();
                    if (email.isNotEmpty) {
                      handleUserFlow(context, email);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a valid email.')),
                      );
                    }
                  },
                  child: const Text('Next'),
                ),
              ],
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class VerifyPasswordPage extends StatelessWidget {
  final String email;
  final String storedPassword;
  final VoidCallback onPasswordVerified;

  const VerifyPasswordPage({
    Key? key,
    required this.email,
    required this.storedPassword,
    required this.onPasswordVerified,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final TextEditingController passwordController = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Enter Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                String password = passwordController.text.trim();
                if (password == storedPassword) {
                  onPasswordVerified();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                        Text('Incorrect password. Please try again.')),
                  );
                }
              },
              child: const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}

class NewPasswordPage extends StatelessWidget {
  final String email;
  final bool isNewUser;
  final void Function(BuildContext) onPasswordSet;

  const NewPasswordPage({
    Key? key,
    required this.email,
    required this.isNewUser,
    required this.onPasswordSet,
  }) : super(key: key);

  Future<bool> createOrUpdateUser(String email, String password, BuildContext context) async {
    final String apiUrl = "https://cleaning-app-sand.vercel.app/api/userflutter";
    final Uri uri = Uri.parse(apiUrl);
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No internet connection.')),
      );
      return false;
    }
    try {
      final http.Response response;
      if (isNewUser) {
        response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'image': password,
          }),
        );
      } else {
        response = await http.put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'image': password,
          }),
        );
      }

      return response.statusCode == 200;
    } catch (e) {
      print('Error: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextEditingController passwordController = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Set Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                String password = passwordController.text.trim();
                if (password.length >= 6) {
                  if (await createOrUpdateUser(email, password, context)) {
                    // Move ScaffoldMessenger inside onPressed
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Password set successfully!')),
                    );
                    onPasswordSet(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to set password.')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Password must be at least 6 characters.')),
                  );
                }
              },
              child: const Text('Set Password'),
            ),
          ],
        ),
      ),
    );
  }
}


class UpdateNamePage extends StatefulWidget {
  final String email;

  const UpdateNamePage({Key? key, required this.email}) : super(key: key);

  @override
  _UpdateNamePageState createState() => _UpdateNamePageState();
}

class _UpdateNamePageState extends State<UpdateNamePage> {
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  bool _isLoading = false;

  Future<bool> updateUserName(
      String email, String firstName, String lastName) async {
    final String apiUrl = "https://cleaning-app-sand.vercel.app/api/user";
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No internet connection.')),
      );
      return false;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.put(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'name': '$firstName $lastName',
        }),
      );
      setState(() {
        _isLoading = false;
      });
      return response.statusCode == 200;
    } catch (e) {
      print('Error: $e');
      setState(() {
        _isLoading = false;
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Update Name')),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  controller: firstNameController,
                  decoration: const InputDecoration(
                    labelText: 'First Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: lastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Last Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                    String firstName = firstNameController.text.trim();
                    String lastName = lastNameController.text.trim();

                    if (firstName.isNotEmpty && lastName.isNotEmpty) {
                      if (await updateUserName(
                          widget.email, firstName, lastName)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                              Text('Name updated successfully!')),
                        );
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ProfilePage(email: widget.email, userName: "$firstName $lastName" ,)),
                              (route) => false,
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Failed to update name.')),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Please enter both first and last name.')),
                      );
                    }
                  },
                  child: const Text('Update Name'),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}



class ProfilePage extends StatelessWidget {
  final String email;
  final String userName;

  const ProfilePage({
    Key? key,
    required this.email,
    required this.userName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ratings App',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
      ),
      home: RatingsScreen(
        userEmail: email,
        userName: userName,
      ),
      routes: {
        '/ratings': (context) => RatingsScreen(
          userEmail: email,
          userName: userName,
        ),
      },
    );
  }
}