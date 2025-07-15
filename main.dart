// AhamAI – FINAL-13: Robust Persistence and UI Lifecycle Fix
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:provider/provider.dart';
import 'github_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Color(0xFFF7F7F7),
    statusBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const AhamAIApp());
}

class AhamAIApp extends StatelessWidget {
  const AhamAIApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GitHubService(),
      child: MaterialApp(
        title: 'AhamAI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.grey,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F7F7),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF7F7F7),
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          fontFamily: 'Inter',
        ),
        home: const MainShell(),
      ),
    );
  }
}

// (All widgets from Message to ChatPageState remain exactly the same)
/* ----------------------------------------------------------
   MODELS
---------------------------------------------------------- */
enum Sender { user, bot }

class Message {
  const Message(this.sender, this.text, {this.isStreaming = false});
  final Sender sender;
  final String text;
  final bool isStreaming;
}

/* ----------------------------------------------------------
   MAIN SHELL (Manages State for Bookmarks)
---------------------------------------------------------- */
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  final GlobalKey<ChatPageState> _chatPageKey = GlobalKey<ChatPageState>();

  final List<Message> _bookmarkedMessages = [];

  void _bookmarkMessage(Message message) {
    setState(() {
      if (!_bookmarkedMessages.any((m) => m.text == message.text && m.sender == message.sender)) {
        _bookmarkedMessages.insert(0, message);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: Duration(seconds: 2), content: Text('Message bookmarked!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: Duration(seconds: 2), content: Text('This message is already bookmarked.')),
        );
      }
    });
  }

  void _startNewChat() {
    _chatPageKey.currentState?.startNewChat();
    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
    }
  }

  Widget _buildAnimatedIcon(IconData activeIcon, IconData inactiveIcon, int itemIndex) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
      child: Icon(
        _selectedIndex == itemIndex ? activeIcon : inactiveIcon,
        key: ValueKey<int>(_selectedIndex == itemIndex ? 1 : 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      ChatPage(key: _chatPageKey, onBookmark: _bookmarkMessage),
      const PlaceholderPage(title: 'Discover'),
      const PlaceholderPage(title: 'Characters'),
      SavedPage(bookmarkedMessages: _bookmarkedMessages),
    ];

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('AhamAI', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.account_circle_outlined, size: 28),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile page coming soon!')));
          },
        ),
        actions: [
          IconButton(icon: const Icon(Icons.add_comment_outlined), onPressed: _startNewChat),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          colorScheme: Theme.of(context).colorScheme.copyWith(
                surfaceTint: Colors.transparent,
              ),
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFFF7F7F7),
          elevation: 0,
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: _buildAnimatedIcon(Icons.home_filled, Icons.home_outlined, 0), label: 'Home'),
            BottomNavigationBarItem(icon: _buildAnimatedIcon(Icons.explore, Icons.explore_outlined, 1), label: 'Discover'),
            BottomNavigationBarItem(icon: _buildAnimatedIcon(Icons.people, Icons.people_outline, 2), label: 'Characters'),
            BottomNavigationBarItem(icon: _buildAnimatedIcon(Icons.bookmark, Icons.bookmark_border, 3), label: 'Saved'),
          ],
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.black87,
          unselectedItemColor: Colors.grey.shade600,
          showSelectedLabels: false,
          showUnselectedLabels: false,
        ),
      ),
    );
  }
}


/* ----------------------------------------------------------
   CHAT PAGE
---------------------------------------------------------- */
class ChatPage extends StatefulWidget {
  final void Function(Message) onBookmark;
  const ChatPage({super.key, required this.onBookmark});
  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <Message>[
    const Message(Sender.bot, 'Hi, I’m AhamAI. Ask me anything!', isStreaming: false),
  ];
  bool _awaitingReply = false;
  StreamSubscription? _currentSubscription;
  GenerativeModel? _model;

  final _prompts = ['Explain quantum computing', 'Write a Python snippet', 'Draft an email to my boss', 'Ideas for weekend trip'];

  @override
  void initState() { super.initState(); _initializeGemini(); }
  void _initializeGemini() {
    const apiKey = 'AIzaSyBUiSSswKvLvEK7rydCCRPF50eIDI_KOGc';
    if (apiKey.isNotEmpty) {
      _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
    }
  }
  @override
  void dispose() { _controller.dispose(); _scroll.dispose(); _currentSubscription?.cancel(); super.dispose(); }

  String? _extractFilePath(String prompt) {
    final regex = RegExp(r'([\w/.-]+\.(?:dart|js|py|html|css|json|md|yaml|ts|tsx|jsx)\b)');
    final match = regex.firstMatch(prompt);
    return match?.group(0);
  }

  Future<void> _generateResponse(String prompt) async {
    final githubService = context.read<GitHubService>();
    final filePath = _extractFilePath(prompt);

    if (_model == null) {
      setState(() => _messages.add(const Message(Sender.bot, 'Error: API Key is not configured.', isStreaming: false)));
      return;
    }

    if (githubService.isProjectConnected && filePath != null) {
      setState(() {
        _awaitingReply = true;
        _messages.add(const Message(Sender.bot, 'Accessing repository and analyzing file...', isStreaming: true));
      });
      _scrollDown();
      final result = await githubService.modifyCodeAndCreatePR(
        geminiModel: _model!,
        filePath: filePath,
        modificationRequest: prompt,
      );
      setState(() {
        _messages.last = Message(Sender.bot, result, isStreaming: false);
        _awaitingReply = false;
      });
      _scrollDown();
      return;
    }

    await _currentSubscription?.cancel(); _currentSubscription = null;
    setState(() { _awaitingReply = true; _messages.add(Message(Sender.bot, '', isStreaming: true)); });
    _scrollDown();
    try {
      final contentStream = _model!.generateContentStream([Content.text(prompt)]);
      final buffer = StringBuffer();
      _currentSubscription = contentStream.listen((chunk) {
        buffer.write(chunk.text);
        setState(() => _messages.last = Message(Sender.bot, buffer.toString(), isStreaming: true));
        _scrollDown();
      }, onDone: () {
        setState(() { _messages.last = Message(Sender.bot, buffer.toString(), isStreaming: false); _awaitingReply = false; });
      }, onError: (e) {
        setState(() { _messages.last = Message(Sender.bot, 'An error occurred: $e', isStreaming: false); _awaitingReply = false; });
      });
    } catch (e) {
      setState(() { _messages.last = Message(Sender.bot, 'Failed to generate response: $e', isStreaming: false); _awaitingReply = false; });
    }
  }

  Future<void> _stopStream() async {
    await _currentSubscription?.cancel(); _currentSubscription = null;
    setState(() {
      if (_messages.isNotEmpty && _messages.last.sender == Sender.bot) {
        _messages.last = Message(Sender.bot, _messages.last.text.trim(), isStreaming: false);
      }
      _awaitingReply = false;
    });
  }

  void _regenerateResponse(int botMessageIndex) {
    int userMessageIndex = botMessageIndex - 1;
    if (userMessageIndex >= 0 && _messages[userMessageIndex].sender == Sender.user) {
      String lastUserPrompt = _messages[userMessageIndex].text;
      setState(() => _messages.removeAt(botMessageIndex));
      _generateResponse(lastUserPrompt);
    }
  }

  void startNewChat() {
    setState(() {
      _awaitingReply = false; _currentSubscription?.cancel(); _messages.clear();
      _messages.add(const Message(Sender.bot, 'Fresh chat started. How can I help?', isStreaming: false));
    });
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || _awaitingReply) return;
    _controller.clear();
    setState(() => _messages.add(Message(Sender.user, text)));
    _scrollDown();
    _generateResponse(text);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final emptyChat = _messages.length == 1;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: _messages.length,
            itemBuilder: (_, index) => _MessageBubble(
              message: _messages[index],
              onRegenerate: () => _regenerateResponse(index),
              onBookmark: () => widget.onBookmark(_messages[index]),
            ),
          ),
        ),
        if (emptyChat)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _prompts.map((p) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(p), selected: false,
                            onSelected: (_) { _controller.text = p; _send(); },
                            side: BorderSide.none, backgroundColor: Colors.white,
                            labelStyle: const TextStyle(fontSize: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 1,
                          ),
                        )).toList(),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: SafeArea(
            top: false, left: false, right: false,
            child: _InputBar(
              controller: _controller, onSend: _send, onStop: _stopStream, awaitingReply: _awaitingReply,
            ),
          ),
        ),
      ],
    );
  }
}

/* ----------------------------------------------------------
   MESSAGE BUBBLE & ACTION BUTTONS
---------------------------------------------------------- */
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.onRegenerate, this.onBookmark});
  final Message message; final VoidCallback? onRegenerate; final VoidCallback? onBookmark;

  @override
  Widget build(BuildContext context) {
    final isBot = message.sender == Sender.bot;
    final showActions = isBot && !message.isStreaming && message.text.isNotEmpty && onRegenerate != null;

    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Column(
        crossAxisAlignment: isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            constraints: const BoxConstraints(maxWidth: 640),
            decoration: BoxDecoration(
              color: isBot ? Colors.white : const Color(0xFFE5E5E5),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 1))],
            ),
            child: isBot
                ? MarkdownBody(
                    data: message.text + (message.isStreaming ? '▍' : ''),
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 15, height: 1.45, color: Colors.black87),
                      code: const TextStyle(backgroundColor: Color(0xFFF1F1F1), fontFamily: 'monospace'),
                    ),
                  )
                : Text(message.text, style: const TextStyle(fontSize: 15, height: 1.45, color: Colors.black87)),
          ),
          if (showActions)
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 4, bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionButton(
                    icon: Icons.copy_all_outlined,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 2), content: Text('Copied to clipboard')));
                    },
                  ),
                  const SizedBox(width: 4),
                  _ActionButton(icon: Icons.refresh_rounded, onTap: onRegenerate!),
                  const SizedBox(width: 4),
                  _ActionButton(icon: Icons.bookmark_add_outlined, onTap: onBookmark!),
                ],
              ),
            )
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(16),
        child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(icon, color: Colors.grey.shade600, size: 20)),
      ),
    );
  }
}

/* ----------------------------------------------------------
   INPUT BAR – send / stop toggle
---------------------------------------------------------- */
class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend, required this.onStop, required this.awaitingReply});
  final TextEditingController controller; final VoidCallback onSend; final VoidCallback onStop; final bool awaitingReply;

  // --- This function now correctly handles the UI flow ---
  void _showGitHubBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Important for custom shape
      builder: (_) {
        // We use the same provider instance from the main tree
        return ChangeNotifierProvider.value(
          value: context.read<GitHubService>(),
          child: const GitHubBottomSheet(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            icon: const Icon(Icons.extension_outlined, color: Colors.black54),
            onPressed: () => _showGitHubBottomSheet(context),
          ),
          Expanded(
            child: TextField(
              controller: controller, enabled: !awaitingReply, maxLines: null,
              textCapitalization: TextCapitalization.sentences, cursorColor: Colors.blue, textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Message AhamAI…', border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          IconButton(
            padding: const EdgeInsets.all(12),
            onPressed: awaitingReply ? onStop : onSend,
            icon: Icon(awaitingReply ? Icons.stop_circle : Icons.send_rounded, color: awaitingReply ? Colors.red : Colors.black87),
          ),
        ],
      ),
    );
  }
}

/* ----------------------------------------------------------
   GITHUB BOTTOM SHEET (NEW WIDGET)
---------------------------------------------------------- */
class GitHubBottomSheet extends StatelessWidget {
  const GitHubBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    // Consumer widget rebuilds its child whenever the GitHubService calls notifyListeners()
    return Consumer<GitHubService>(
      builder: (context, service, child) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: Color(0xFFF7F7F7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: FractionallySizedBox(
            heightFactor: 0.65,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: service.isLoading
                    ? const Center(key: ValueKey('loader'), child: CircularProgressIndicator(color: Colors.black87))
                    : _buildContent(context, service),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, GitHubService service) {
    // This logic tree now correctly directs the UI
    if (!service.isSignedIn) {
      return _buildSignedOutView(context, service);
    }
    if (service.isProjectConnected) {
      return _buildProjectConnectedView(context, service);
    }
    return _buildRepoSelectionView(context, service);
  }

  Widget _buildSignedOutView(BuildContext context, GitHubService service) {
    return Column(
      key: const ValueKey('signedOut'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.code_off_rounded, size: 80, color: Colors.grey.shade400),
        const SizedBox(height: 24),
        const Text(
          'Connect to GitHub',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF424242)),
        ),
        const SizedBox(height: 8),
        Text(
          'Allow AhamAI to access your repositories to read files, create branches, and open pull requests.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.4),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () {
            // No complex logic needed here. Just call signIn. The Consumer will handle the rebuild.
            service.signIn();
          },
          icon: const Icon(Icons.link),
          label: const Text('Connect Your Project'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Widget _buildRepoSelectionView(BuildContext context, GitHubService service) {
    return Column(
      key: const ValueKey('repoSelection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (service.currentUser?.avatarUrl != null)
              CircleAvatar(
                backgroundImage: NetworkImage(service.currentUser!.avatarUrl),
                radius: 20,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome, ${service.currentUser?.login ?? ''}!',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const Text('Select a repository to begin', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Disconnect from GitHub',
              onPressed: () => service.signOut(),
            )
          ],
        ),
        const Divider(height: 32),
        const Text('Your Repositories', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<GitHubRepo>>(
            future: service.listRepositories(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Colors.black87));
              }
              if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('Could not load repositories.'));
              }
              final repos = snapshot.data!;
              return ListView.builder(
                itemCount: repos.length,
                itemBuilder: (context, index) {
                  final repo = repos[index];
                  return ListTile(
                    title: Text(repo.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(repo.owner),
                    leading: const Icon(Icons.book_outlined),
                    onTap: () {
                      service.selectProject(repo);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProjectConnectedView(BuildContext context, GitHubService service) {
    return Column(
      key: const ValueKey('projectConnected'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline_rounded, size: 80, color: Colors.green.shade600),
        const SizedBox(height: 24),
        const Text(
          'Project Connected',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF424242)),
        ),
        const SizedBox(height: 8),
        Text(
          'AhamAI is now connected to:\n${service.activeRepo?.fullName}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade700, height: 1.4),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => service.disconnectProject(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade300,
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Disconnect Project'),
        ),
        TextButton(
          onPressed: () {
            service.disconnectProject();
          },
          child: const Text('Switch to another project', style: TextStyle(color: Colors.black54)),
        ),
      ],
    );
  }
}


/* ----------------------------------------------------------
   SAVED PAGE & PLACEHOLDER
---------------------------------------------------------- */
class SavedPage extends StatelessWidget {
  final List<Message> bookmarkedMessages;
  const SavedPage({super.key, required this.bookmarkedMessages});

  @override
  Widget build(BuildContext context) {
    if (bookmarkedMessages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_outline_rounded, size: 80, color: Colors.grey.shade400),
              const SizedBox(height: 24),
              const Text('No Bookmarks Yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF424242))),
              const SizedBox(height: 8),
              Text(
                'Tap the bookmark icon on a message in your chat to save it here for later.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 8,
        bottom: kBottomNavigationBarHeight + 40,
      ),
      itemCount: bookmarkedMessages.length,
      itemBuilder: (context, index) {
        final message = bookmarkedMessages[index];
        return _MessageBubble(message: message);
      },
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title Page',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.grey),
      ),
    );
  }
}