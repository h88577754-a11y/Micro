import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// सुनिश्चित करें कि यह फ़ाइल आपके प्रोजेक्ट में मौजूद है!
import 'firebase_options.dart'; 

// =======================================================
// 1. MAIN APP WIDGET
// =======================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase को शुरू करें
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform, 
    );
  } catch (e) {
    // अगर Firebase शुरू करने में एरर आए (जैसे firebase_options.dart नहीं मिली)
    print("Error initializing Firebase: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Micro Task App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // App की शुरुआत में लॉगिन स्थिति चेक करें
      home: const AuthStatusCheck(), 
    );
  }
}

class AuthStatusCheck extends StatelessWidget {
  const AuthStatusCheck({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          // अगर यूज़र लॉगिन है, तो होम स्क्रीन पर भेजें
          return const WalletScreen();
        }
        // अगर लॉगिन नहीं है, तो लॉगिन स्क्रीन पर भेजें
        return const LoginScreen();
      },
    );
  }
}

// =======================================================
// 2. AUTHENTICATION & SERVICE FUNCTIONS
// =======================================================

// --- [A] SIGNUP Function ---
Future<String?> signUpUser(String email, String password) async {
  try {
    final UserCredential userCredential =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Firestore में नया यूज़र डेटा (वॉलेट बैलेंस 0.0 के साथ) सेव करें
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userCredential.user!.uid)
        .set({
      'email': email,
      'walletBalance': 0.0,
      'isBlocked': false, 
      'createdAt': Timestamp.now(),
    });

    return 'Success';
  } on FirebaseAuthException catch (e) {
    return e.message; 
  } catch (e) {
    return e.toString();
  }
}

// --- [B] SIGNIN Function ---
Future<String?> signInUser(String email, String password) async {
  try {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return 'Success';
  } on FirebaseAuthException catch (e) {
    return e.message;
  }
}

// --- [C] LOGOUT Function ---
Future<void> signOutUser() async {
  await FirebaseAuth.instance.signOut();
}

// --- [D] ADD MONEY/TASK COMPLETION Function ---
Future<String?> completeTaskAndReward(double rewardAmount, String taskName) async {
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return "User not logged in.";

  final userRef = FirebaseFirestore.instance.collection('users').doc(userId);

  try {
    // Firestore Transaction का उपयोग करके सुरक्षा सुनिश्चित करें
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final double currentBalance = userSnapshot.data()?['walletBalance'] ?? 0.0;
      
      final double newBalance = currentBalance + rewardAmount;
      
      // 1. वॉलेट अपडेट करें
      transaction.update(userRef, {'walletBalance': newBalance});
      
      // 2. ट्रांज़ैक्शन हिस्ट्री रिकॉर्ड करें
      FirebaseFirestore.instance.collection('transactions').add({
        'userId': userId,
        'type': 'Credit',
        'amount': rewardAmount,
        'description': 'Task Reward: $taskName',
        'timestamp': FieldValue.serverTimestamp(),
      });
    });

    return "Task completed! ₹$rewardAmount added.";
  } catch (e) {
    return "Failed to update wallet: $e";
  }
}

// --- [E] WITHDRAWAL REQUEST Function ---
Future<String?> requestWithdrawal(double amount, String upiId) async {
  final User? user = FirebaseAuth.instance.currentUser;
  if (user == null) return "User not logged in.";
  
  if (amount <= 0) return "Please enter a valid amount."; // मिनिमम अमाउंट यहाँ सेट किया जा सकता है

  final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  final currentBalance = userDoc.data()?['walletBalance'] ?? 0.0;

  if (amount > currentBalance) {
    return "Insufficient balance.";
  }

  // विथड्रावल रिक्वेस्ट को 'withdrawal_requests' कलेक्शन में सेव करें
  await FirebaseFirestore.instance.collection('withdrawal_requests').add({
    'userId': user.uid,
    'email': user.email,
    'amount': amount,
    'upiId': upiId,
    'status': 'Pending', // Admin द्वारा प्रोसेस किया जाएगा
    'timestamp': FieldValue.serverTimestamp(),
  });
  
  // वॉलेट से राशि तुरंत घटा दें
  await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
    'walletBalance': currentBalance - amount,
  });

  return 'Withdrawal request submitted successfully! Status: Pending.';
}

// =======================================================
// 3. USER INTERFACE (SCREENS)
// =======================================================

// --- [A] LOGIN / SIGNUP SCREEN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool isLogin = true;
  String? errorMessage;

  void _submitAuth() async {
    // ... [Previous Login Logic - unchanged] ...
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    String? result;

    setState(() {
      errorMessage = null; 
    });

    if (isLogin) {
      result = await signInUser(email, password);
    } else {
      result = await signUpUser(email, password);
    }

    if (result != 'Success') {
      setState(() {
        errorMessage = result;
      });
    }
    // Success will be handled by AuthStatusCheck widget 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Login' : 'Signup')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
            const SizedBox(height: 20),
            if (errorMessage != null) 
              Text(errorMessage!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _submitAuth,
              child: Text(isLogin ? 'Login' : 'Signup'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  isLogin = !isLogin;
                });
              },
              child: Text(isLogin ? 'Need an account? Signup' : 'Already have an account? Login'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- [B] WALLET / HOME SCREEN ---
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Micro Task Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              signOutUser(); 
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wallet Balance Display (Real-time data)
            const Text("Your Wallet:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }

                final data = snapshot.data!.data() as Map<String, dynamic>?;
                final double balance = data?['walletBalance'] ?? 0.0;
                final bool isBlocked = data?['isBlocked'] ?? false;

                if (isBlocked) {
                  return const Text("ACCOUNT BLOCKED", style: TextStyle(color: Colors.red, fontSize: 18));
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    "₹ ${balance.toStringAsFixed(2)}",
                    style: const TextStyle(fontSize: 40, color: Colors.green, fontWeight: FontWeight.w900),
                  ),
                );
              },
            ),
            
            // --- Sample Tasks ---
            const Divider(),
            const Text("Available Microtasks:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            
            // 1. Spin Wheel Example
            TaskTile(
              title: "Spin Wheel (₹5 Reward)", 
              reward: 5.0, 
              onTap: () async {
                // यहाँ स्पिन व्हील UI/Logic (जिसे आपको खुद बनाना होगा) के बाद यह फंक्शन कॉल होगा
                const double wonAmount = 5.0; 
                final result = await completeTaskAndReward(wonAmount, "Spin Wheel");
                // ScaffoldMessenger यूज़र को तुरंत फीडबैक देने के लिए
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result!)));
              },
            ),

            // 2. Survey Example
            TaskTile(
              title: "Complete Survey (₹15 Reward)", 
              reward: 15.0, 
              onTap: () async {
                final result = await completeTaskAndReward(15.0, "Quick Survey");
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result!)));
              },
            ),

            // --- Withdrawal Option ---
            const Divider(),
            ElevatedButton.icon(
              icon: const Icon(Icons.payment),
              label: const Text("Request Withdrawal (UPI/Redeem Code)"),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const WithdrawalScreen(),
                ));
              },
            ),

            // --- Withdrawal History ---
            const Divider(),
            const Text("Withdrawal History:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            WithdrawalHistoryList(userId: userId!),
            
            // --- About/Contact ---
            const Divider(),
            Text("Created by: Aryan"),
            Text("Contact: kumayan7488@gmail.com"),
          ],
        ),
      ),
    );
  }
}

// --- Task Tile Component (Reusable UI) ---
class TaskTile extends StatelessWidget {
  final String title;
  final double reward;
  final VoidCallback onTap;

  const TaskTile({super.key, required this.title, required this.reward, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: Text("+₹${reward.toStringAsFixed(2)}", style: const TextStyle(color: Colors.blue)),
      leading: const Icon(Icons.star),
      onTap: onTap,
    );
  }
}

// --- Withdrawal Request Screen ---
class WithdrawalScreen extends StatefulWidget {
  const WithdrawalScreen({super.key});

  @override
  State<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends State<WithdrawalScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _upiController = TextEditingController();
  String? statusMessage;

  void _submitWithdrawal() async {
    final double amount = double.tryParse(_amountController.text) ?? 0.0;
    final String upiId = _upiController.text.trim();

    if (amount <= 0 || upiId.isEmpty) {
      setState(() => statusMessage = "Please enter valid amount and UPI ID/Email.");
      return;
    }

    // विथड्रावल फ़ंक्शन को कॉल करें
    final result = await requestWithdrawal(amount, upiId);
    setState(() => statusMessage = result);
    
    if (result!.contains('successfully')) {
      _amountController.clear();
      _upiController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Request Withdrawal")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount to Withdraw'),
            ),
            TextField(
              controller: _upiController,
              decoration: const InputDecoration(labelText: 'Your UPI ID or Email for Redeem Code'),
            ),
            const SizedBox(height: 20),
            if (statusMessage != null)
              Text(statusMessage!, style: TextStyle(color: statusMessage!.contains('successfully') ? Colors.green : Colors.red)),
            ElevatedButton(
              onPressed: _submitWithdrawal,
              child: const Text("Submit Request"),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Withdrawal History List ---
class WithdrawalHistoryList extends StatelessWidget {
  final String userId;
  
  const WithdrawalHistoryList({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // केवल इस यूज़र की रिक्वेस्ट दिखाएं, नवीनतम पहले
      stream: FirebaseFirestore.instance
          .collection('withdrawal_requests')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: Text("Loading History..."));

        final requests = snapshot.data!.docs;

        if (requests.isEmpty) {
          return const Text("No withdrawal history found.");
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index].data() as Map<String, dynamic>;
            final String status = request['status'] ?? 'Pending';
            final double amount = request['amount'] ?? 0.0;
            
            Color statusColor;
            if (status == 'Completed') {
              statusColor = Colors.green;
            } else if (status == 'Pending') {
              statusColor = Colors.orange;
            } else {
              statusColor = Colors.red;
            }

            return ListTile(
              title: Text("₹${amount.toStringAsFixed(2)}"),
              subtitle: Text("Status: $status (To: ${request['upiId']})"),
              trailing: Icon(Icons.circle, color: statusColor, size: 10),
            );
          },
        );
      },
    );
  }
}
