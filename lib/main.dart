import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const LongTracksRadioApp());
}

class LongTracksRadioApp extends StatelessWidget {
  const LongTracksRadioApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Long Tracks Radio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0a0a),
        primaryColor: const Color(0xFFE8943A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFE8943A),
          secondary: const Color(0xFFF0AD5E),
          surface: const Color(0xFF141414),
          background: const Color(0xFF0a0a0a),
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0a0a0a),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// AUDIO HANDLER - Gère la lecture en arrière-plan
class RadioAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  final StreamController<void> _stateController = StreamController<void>.broadcast();
  late Completer<void> _initCompleter = Completer(); 
  
  String currentTrack = 'En cours de chargement...';
  String currentArtist = '';
  String? artworkUrl;
  Timer? _metadataTimer;
  List<TrackInfo> trackHistory = [];
  String? _lastTrackId;

  Stream<void> get stateStream => _stateController.stream;

  RadioAudioHandler() {
    _init();
  }

 Future<void> _init() async {
  await _player.setLoopMode(LoopMode.one);
  await _player.setVolume(0.7);

  _player.playbackEventStream.listen((event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
    ));
    _notifyListeners();
  });

  // AJOUTEZ : Attendre le premier chargement des métadonnées
  await _fetchMetadata();
  
  // Puis continuer avec les mises à jour régulières
  _startMetadataFetching();
  _initCompleter.complete();  
}

  void _startMetadataFetching() {
    _fetchMetadata();
    _metadataTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchMetadata();
    });
  }

  Future<void> _fetchMetadata() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.radiojar.com/api/stations/z21997mep5nwv/now_playing/'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newTrack = data['title'] ?? 'Titre inconnu';
        final newArtist = data['artist'] ?? '';
        final newArtwork = data['thumb'];
        
        final trackId = '$newTrack-$newArtist';
        
        if (_lastTrackId != null && _lastTrackId != trackId) {
          _addToHistory(currentTrack, currentArtist, artworkUrl);
        }
        
        _lastTrackId = trackId;
        currentTrack = newTrack;
        currentArtist = newArtist;
        artworkUrl = newArtwork;

        // Mettre à jour la notification
        mediaItem.add(MediaItem(
          id: 'long_tracks_radio',
          title: currentTrack,
          artist: currentArtist,
          artUri: artworkUrl != null ? Uri.parse(artworkUrl!) : null,
          album: 'Long Tracks Radio',
        ));
        
        _notifyListeners();
      }
    } catch (e) {
      print('Erreur metadata: $e');
    }
  }

  void _addToHistory(String track, String artist, String? artwork) {
    final trackInfo = TrackInfo(
      title: track,
      artist: artist,
      artworkUrl: artwork,
      timestamp: DateTime.now(),
    );
    
    trackHistory.insert(0, trackInfo);
    
    if (trackHistory.length > 5) {
      trackHistory.removeLast();
    }
    
    print('Historique mis à jour : ${trackHistory.length} morceaux');
  }

  @override
  Future<void> play() async {
    try {
      await _player.setUrl('http://stream.radiojar.com/z21997mep5nwv');
      await _player.play();
    } catch (e) {
      print('Erreur play: $e');
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  void _notifyListeners() {
    _stateController.add(null);
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'getHistory') {
      // Méthode pour récupérer l'historique si besoin
    }
  }
}

// SINGLETON pour accéder au handler partout
class PlayerService {
  static RadioAudioHandler? _handler;
  
  static Future<RadioAudioHandler> getHandler() async {
    if (_handler == null) {
      _handler = await AudioService.init(
        builder: () => RadioAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.longtracks.radio.channel.audio',
          androidNotificationChannelName: 'Long Tracks Radio',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
        ),
      );
      await _handler!._initCompleter.future;
    }
    return _handler!;
  }

  static RadioAudioHandler? get handler => _handler;
}

class TrackInfo {
  final String title;
  final String artist;
  final String? artworkUrl;
  final DateTime timestamp;

  TrackInfo({
    required this.title,
    required this.artist,
    this.artworkUrl,
    required this.timestamp,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _selectedIndex = 0;
  RadioAudioHandler? _handler;
  late Future<RadioAudioHandler> _handlerFuture;

  @override
  void initState() {
    super.initState();
    _handlerFuture = PlayerService.getHandler();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      print('App resumed');
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RadioAudioHandler>(
      future: _handlerFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFE8943A)),
                  SizedBox(height: 16),
                  Text('Démarrage...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          );
        }

        _handler = snapshot.data;

        return Scaffold(
          body: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: const [
              PlayerPage(),
              HistoryPage(),
              ProgramPage(),
              AboutPage(),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: const Color(0xFFE8943A).withOpacity(0.12),
                  width: 1,
                ),
              ),
            ),
            child: BottomNavigationBar(
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.radio),
                  label: 'Écouter',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.history),
                  label: 'Historique',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.schedule),
                  label: 'Programme',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.info_outline),
                  label: 'À propos',
                ),
              ],
              currentIndex: _selectedIndex,
              selectedItemColor: const Color(0xFFE8943A),
              unselectedItemColor: const Color(0xFF7a756e),
              backgroundColor: const Color(0xFF141414),
              onTap: _onItemTapped,
              type: BottomNavigationBarType.fixed,
            ),
          ),
        );
      },
    );
  }
}

// PAGE PLAYER
class PlayerPage extends StatelessWidget {
  const PlayerPage({Key? key}) : super(key: key);

    @override
    Widget build(BuildContext context) {
      final handler = PlayerService.handler;

      if (handler == null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFE8943A)),
              SizedBox(height: 16),
              Text('Initialisation...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        );
      }

      // Interface affichée DIRECTEMENT sans attendre le stream
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1410), Color(0xFF0a0a0a)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('LONG TRACKS', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFE8943A), letterSpacing: 4)),
                  Text('RADIO', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: Colors.white70, letterSpacing: 8)),
                  SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Badge(text: '🎵 Versions longues'),
                      SizedBox(width: 12),
                      _Badge(text: '🌀 24h/24'),
                    ],
                  ),
                  SizedBox(height: 30),
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: Color(0xFFE8943A).withOpacity(0.3), blurRadius: 30, offset: Offset(0, 10))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: handler.artworkUrl != null
                          ? Image.network(
                              handler.artworkUrl!,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFE8943A),
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return _defaultArtwork();
                              },
                            )
                          : _defaultArtwork(),
                    ),
                  ),
                  SizedBox(height: 30),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      children: [
                        Text(handler.currentTrack, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                        SizedBox(height: 8),
                        Text(handler.currentArtist, style: TextStyle(fontSize: 16, color: Color(0xFFF0AD5E)), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  SizedBox(height: 30),
                  StreamBuilder<PlaybackState>(
                    stream: handler.playbackState,
                    initialData: PlaybackState(controls: [MediaControl.play], processingState: AudioProcessingState.loading, playing: false),
                    builder: (context, snapshot) {
                      final playing = snapshot.data?.playing ?? false;
                      return GestureDetector(
                        onTap: () async {
                          if (playing) await handler.pause();
                          else await handler.play();
                        },
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFE8943A),
                            boxShadow: [BoxShadow(color: Color(0xFFE8943A).withOpacity(0.4), blurRadius: 20, offset: Offset(0, 5))],
                          ),
                          child: Icon(playing ? Icons.pause : Icons.play_arrow, size: 40, color: Colors.white),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      );
    }
  

  Widget _defaultArtwork() {
    return Container(
      color: Color(0xFF1c1c1c),
      child: Icon(
        Icons.music_note,
        size: 120,
        color: Color(0xFFE8943A),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;

  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1c1c1c),
        border: Border.all(
          color: const Color(0xFFE8943A).withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFFF0AD5E),
          fontWeight: FontWeight.w500,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// PAGE HISTORIQUE
class HistoryPage extends StatelessWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final handler = PlayerService.handler;

    if (handler == null) {
      return Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<void>(
      stream: handler.stateStream,
      builder: (context, snapshot) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1a1410), Color(0xFF0a0a0a)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'HISTORIQUE',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE8943A),
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: handler.trackHistory.isEmpty
                      ? Center(
                          child: Text(
                            'Aucun historique pour le moment\nLancez la radio pour commencer',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemCount: handler.trackHistory.length,
                          itemBuilder: (context, index) {
                            final track = handler.trackHistory[index];
                            return _buildTrackCard(track, index);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackCard(TrackInfo track, int index) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      color: Color(0xFF1c1c1c),
      child: ListTile(
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: track.artworkUrl != null
                ? Image.network(
                    track.artworkUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Color(0xFF282828),
                        child: Icon(
                          Icons.music_note,
                          color: Color(0xFFE8943A),
                        ),
                      );
                    },
                  )
                : Container(
                    color: Color(0xFF282828),
                    child: Icon(
                      Icons.music_note,
                      color: Color(0xFFE8943A),
                    ),
                  ),
          ),
        ),
        title: Text(
          track.title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track.artist,
              style: TextStyle(
                color: Color(0xFFF0AD5E),
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4),
            Text(
              _formatTimestamp(track.timestamp),
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Color(0xFFE8943A).withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '#${index + 1}',
            style: TextStyle(
              color: Color(0xFFE8943A),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'À l\'instant';
    } else if (difference.inMinutes < 60) {
      return 'Il y a ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Il y a ${difference.inHours}h';
    } else {
      return '${time.day}/${time.month} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}

// PAGE PROGRAMME
class ProgramPage extends StatelessWidget {
  const ProgramPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a1410), Color(0xFF0a0a0a)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'PROGRAMME',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE8943A),
                  letterSpacing: 2,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildDayCard('Lundi', true, [
                    _Slot('00h–18h', 'Version XL', 'Morceaux longs de tous genres'),
                    _Slot('18h–20h', 'Version Maxi', 'Les versions les plus longues'),
                    _Slot('20h–22h', 'Version Live', 'Enregistrements live légendaires'),
                    _Slot('22h–00h', 'Version Rock et Métal', 'Rock progressif, métal épique'),
                  ]),
                  _buildDayCard('Mardi', false, [
                    _Slot('00h–18h', 'Version XL', 'Morceaux longs de tous genres'),
                    _Slot('18h–20h', 'Version Maxi', 'Les versions les plus longues'),
                    _Slot('20h–22h', 'Version Live', 'Enregistrements live légendaires'),
                    _Slot('22h–00h', 'Version Rock et Métal', 'Rock progressif, métal épique'),
                  ]),
                  _buildDayCard('Mercredi', false, [
                    _Slot('00h–18h', 'Version XL', 'Morceaux longs de tous genres'),
                    _Slot('18h–20h', 'Version Maxi', 'Les versions les plus longues'),
                    _Slot('20h–22h', 'Version Live', 'Enregistrements live légendaires'),
                    _Slot('22h–00h', 'Version Rock et Métal', 'Rock progressif, métal épique'),
                  ]),
                  _buildDayCard('Jeudi', false, [
                    _Slot('00h–18h', 'Version XL', 'Morceaux longs de tous genres'),
                    _Slot('18h–20h', 'Version Maxi', 'Les versions les plus longues'),
                    _Slot('20h–22h', 'Version Live', 'Enregistrements live légendaires'),
                    _Slot('22h–00h', 'Version Rock et Métal', 'Rock progressif, métal épique'),
                  ]),
                  _buildDayCard('Vendredi', false, [
                    _Slot('00h–18h', 'Version XL', 'Morceaux longs de tous genres'),
                    _Slot('18h–20h', 'Version Maxi', 'Les versions les plus longues'),
                    _Slot('20h–22h', 'Version Live', 'Enregistrements live légendaires'),
                    _Slot('22h–00h', 'Version Rock et Métal', 'Rock progressif, métal épique'),
                  ]),
                  _buildDayCard('Samedi', false, [
                    _Slot('00h–18h', 'Version XL', 'Morceaux longs de tous genres'),
                    _Slot('18h–20h', 'Version Maxi', 'Les versions les plus longues'),
                    _Slot('20h–00h', 'Version Dance', 'Dance, electro et disco non-stop'),
                  ]),
                  _buildDayCard('Dimanche', false, [
                    _Slot('00h–18h', 'Version XL', 'Morceaux longs de tous genres'),
                    _Slot('18h–20h', 'Version Maxi', 'Les versions les plus longues'),
                    _Slot('20h–00h', 'Version Dance', 'Dance, electro et disco non-stop'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(String day, bool isExpanded, List<_Slot> slots) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      color: Color(0xFF1c1c1c),
      child: ExpansionTile(
        title: Text(
          day,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        initiallyExpanded: isExpanded,
        iconColor: Color(0xFFE8943A),
        collapsedIconColor: Color(0xFF7a756e),
        children: slots.map((slot) {
          return ListTile(
            leading: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Color(0xFFE8943A).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                slot.time,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFE8943A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              slot.name,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              slot.description,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Slot {
  final String time;
  final String name;
  final String description;

  _Slot(this.time, this.name, this.description);
}

// PAGE À PROPOS
class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a1410), Color(0xFF0a0a0a)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'À PROPOS',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE8943A),
                    letterSpacing: 2,
                  ),
                ),
              ),
              SizedBox(height: 40),
              Text(
                'Notre mission',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Long Tracks Radio est née d\'une simple idée : les meilleurs morceaux de musique méritent d\'être écoutés dans leur intégralité. Pas de cuts, pas de versions 3 min 30 — ici, chaque titre respire librement. Une radio créée par des passionnés, pour des passionnés.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white70,
                  height: 1.6,
                ),
              ),
              SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStat('24/7', 'Diffusion continue'),
                  _buildStat('0', 'Publicités'),
                  _buildStat('∞', 'Genres musicaux'),
                ],
              ),
              SizedBox(height: 50),
              Text(
                'Contact',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              _buildContactTile(
                icon: Icons.email_outlined,
                label: 'Email',
                value: 'contact@long-tracks-radio.com',
              ),
              SizedBox(height: 16),
              _buildContactTile(
                icon: Icons.language,
                label: 'Site web',
                value: 'www.long-tracks-radio.com',
              ),
              SizedBox(height: 50),
              Center(
                child: Column(
                  children: [
                    Text(
                      'Version 1.1.0',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white38,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '© 2025 Long Tracks Radio',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE8943A),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white60,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildContactTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF1c1c1c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(0xFFE8943A).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFE8943A).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Color(0xFFE8943A),
              size: 24,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}