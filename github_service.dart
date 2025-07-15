import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart'; // <-- FIX: Corrected the import path

// --- DATA MODELS ---
class GitHubUser {
  final String login;
  final String avatarUrl;
  GitHubUser({required this.login, required this.avatarUrl});
}

class GitHubRepo {
  final String name;
  final String owner;
  final String defaultBranch;
  const GitHubRepo({required this.name, required this.owner, required this.defaultBranch});

  String get fullName => '$owner/$name';
}

// --- GITHUB SERVICE ---
class GitHubService extends ChangeNotifier {
  static const String _clientId = 'Ov23li9BRKnUAbjqCOL1';
  static const String _clientSecret = '26e6e65e2a69ee84b3e05f26c5494d7285c4e5fb';
  static const String _callbackUrlScheme = 'ahamaiapp';

  // --- SharedPreferences Keys ---
  static const String _tokenKey = 'github_access_token';
  static const String _repoFullNameKey = 'github_active_repo_full_name';
  static const String _repoBranchKey = 'github_active_repo_branch';

  String? _accessToken;
  GitHubUser? _currentUser;
  GitHubRepo? _activeRepo;
  bool _isLoading = false;

  bool get isSignedIn => _accessToken != null;
  bool get isProjectConnected => _activeRepo != null;
  GitHubUser? get currentUser => _currentUser;
  GitHubRepo? get activeRepo => _activeRepo;
  bool get isLoading => _isLoading;

  GitHubService() {
    _loadSession();
  }

  Future<void> _setLoading(bool value) async {
    _isLoading = value;
    notifyListeners();
  }

  // --- Session Management ---
  Future<void> _loadSession() async {
    await _setLoading(true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null && token.isNotEmpty) {
      _accessToken = token;
      await _fetchUserDetails();
      await _loadActiveRepo();
    }
    await _setLoading(false);
  }
  
  Future<void> _saveActiveRepo(GitHubRepo repo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_repoFullNameKey, repo.fullName);
    await prefs.setString(_repoBranchKey, repo.defaultBranch);
  }

  Future<void> _loadActiveRepo() async {
    final prefs = await SharedPreferences.getInstance();
    final fullName = prefs.getString(_repoFullNameKey);
    final branch = prefs.getString(_repoBranchKey);
    if (fullName != null && branch != null) {
      final parts = fullName.split('/');
      _activeRepo = GitHubRepo(owner: parts[0], name: parts[1], defaultBranch: branch);
    }
  }

  Future<void> _clearActiveRepo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_repoFullNameKey);
    await prefs.remove(_repoBranchKey);
  }

  Future<void> signIn() async {
    await _setLoading(true);
    try {
      final url = Uri.https('github.com', '/login/oauth/authorize', {
        'client_id': _clientId,
        'scope': 'repo,user:email',
      });
      final result = await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: _callbackUrlScheme);
      final code = Uri.parse(result).queryParameters['code'];
      if (code != null) {
        await _exchangeCodeForToken(code);
      }
    } catch (e) {
      // User cancelled
    } finally {
      await _setLoading(false);
    }
  }

  Future<void> _exchangeCodeForToken(String code) async {
    try {
      final response = await http.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: {'Accept': 'application/json'},
        body: {'client_id': _clientId, 'client_secret': _clientSecret, 'code': code},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.containsKey('access_token')) {
          _accessToken = data['access_token'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenKey, _accessToken!);
          await _fetchUserDetails();
        }
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _fetchUserDetails() async {
    if (!isSignedIn) return;
    final response = await _get('https://api.github.com/user');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _currentUser = GitHubUser(login: data['login'], avatarUrl: data['avatar_url']);
    }
  }

  Future<void> signOut() async {
    await _setLoading(true);
    _accessToken = null;
    _currentUser = null;
    _activeRepo = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await _clearActiveRepo();
    await _setLoading(false);
  }

  Future<List<GitHubRepo>> listRepositories() async {
    if (!isSignedIn) return [];
    List<GitHubRepo> repos = [];
    await _setLoading(true);
    try {
        final response = await _get('https://api.github.com/user/repos?sort=updated&per_page=50');
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          repos = data.map((repo) => GitHubRepo(name: repo['name'], owner: repo['owner']['login'], defaultBranch: repo['default_branch'])).toList();
        }
    } catch (e) {
        // handle error
    }
    await _setLoading(false);
    return repos;
  }

  Future<void> selectProject(GitHubRepo repo) async {
    await _setLoading(true);
    _activeRepo = repo;
    await _saveActiveRepo(repo);
    await _setLoading(false);
  }

  Future<void> disconnectProject() async {
    await _setLoading(true);
    _activeRepo = null;
    await _clearActiveRepo();
    await _setLoading(false);
  }

  Future<http.Response> _get(String url) => http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $_accessToken'});
  Future<http.Response> _post(String url, {required Map<String, dynamic> body}) => http.post(Uri.parse(url), headers: {'Authorization': 'Bearer $_accessToken', 'Content-Type': 'application/json'}, body: json.encode(body));
  Future<http.Response> _put(String url, {required Map<String, dynamic> body}) => http.put(Uri.parse(url), headers: {'Authorization': 'Bearer $_accessToken', 'Content-Type': 'application/json'}, body: json.encode(body));

  Future<String> modifyCodeAndCreatePR({
    required GenerativeModel geminiModel,
    required String filePath,
    required String modificationRequest,
  }) async {
    if (!isProjectConnected) return "Error: No project connected.";
    await _setLoading(true);
    try {
      final branchName = _activeRepo!.defaultBranch;
      final refResponse = await _get('https://api.github.com/repos/${_activeRepo!.fullName}/git/ref/heads/$branchName');
      if (refResponse.statusCode != 200) return "Error: Could not find main branch.";
      final latestCommitSha = json.decode(refResponse.body)['object']['sha'];
      final contentResponse = await _get('https://api.github.com/repos/${_activeRepo!.fullName}/contents/$filePath');
      if (contentResponse.statusCode != 200) return "Error: Could not find file '$filePath'. Make sure the path is correct.";
      final contentData = json.decode(contentResponse.body);
      final fileSha = contentData['sha'];
      final originalContent = utf8.decode(base64.decode(contentData['content']));
      final generationPrompt =
          "You are an expert programmer. Your task is to modify a code file based on a user request. "
          "Read the original file content, apply the requested changes, and return ONLY the full, updated content of the file. "
          "Do not add any explanations, introductory text, or markdown code blocks.\n\n"
          "USER REQUEST: \"$modificationRequest\"\n\n"
          "ORIGINAL FILE CONTENT of `$filePath`:\n"
          "```\n$originalContent\n```";
      final geminiResponse = await geminiModel.generateContent([Content.text(generationPrompt)]);
      final newContent = geminiResponse.text;
      if (newContent == null || newContent.isEmpty) {
        return "Error: The AI did not return any content. Please try a different request.";
      }
      final newBranchName = 'ahamai-patch-${DateTime.now().millisecondsSinceEpoch}';
      await _post('https://api.github.com/repos/${_activeRepo!.fullName}/git/refs', body: {
        'ref': 'refs/heads/$newBranchName',
        'sha': latestCommitSha,
      });
      await _put('https://api.github.com/repos/${_activeRepo!.fullName}/contents/$filePath', body: {
        'message': 'feat: Modified $filePath via AhamAI',
        'content': base64.encode(utf8.encode(newContent)),
        'sha': fileSha,
        'branch': newBranchName,
      });
      final prResponse = await _post('https://api.github.com/repos/${_activeRepo!.fullName}/pulls', body: {
        'title': 'AhamAI Proposed Changes for $filePath',
        'head': newBranchName,
        'base': branchName,
        'body': 'These changes were generated by AhamAI based on the user prompt: "$modificationRequest"',
      });
      if (prResponse.statusCode != 201) return "Error: Could not create a pull request. The changes have been committed to the branch '$newBranchName'.";
      final prUrl = json.decode(prResponse.body)['html_url'];
      return "Success! I've opened a pull request for you to review at:\n$prUrl";
    } catch (e) {
      return "An unexpected error occurred: $e";
    } finally {
      await _setLoading(false);
    }
  }
}
