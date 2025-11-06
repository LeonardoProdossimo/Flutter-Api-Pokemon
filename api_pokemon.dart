import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // For Future and async

/// Represents a single Pokémon entry from the API.
class Pokemon {
  final String name;
  final String url;
  final String imageUrl; // Added for the Pokémon's image

  const Pokemon({required this.name, required this.url, required this.imageUrl});

  /// Creates a [Pokemon] object from a JSON map.
  factory Pokemon.fromJson(Map<String, dynamic> json) {
    final String name = json['name'] as String;
    final String url = json['url'] as String;

    // Extract ID from the URL to construct the image URL
    // Example URL: https://pokeapi.co/api/v2/pokemon/1/
    final List<String> parts = url.split('/');
    // Filter out empty strings to handle trailing slashes correctly
    final List<String> nonBlankParts = parts.where((String element) => element.isNotEmpty).toList();
    // The ID is the last numeric segment in the URL
    final String idString = nonBlankParts.last;

    // Construct the official artwork image URL
    final String imageUrl =
        'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/$idString.png';

    return Pokemon(name: name, url: url, imageUrl: imageUrl);
  }
}

/// Represents the response structure for a list of Pokémon from the API.
class PokemonListResponse {
  final int count;
  final String? next;
  final String? previous;
  final List<Pokemon> results;

  const PokemonListResponse({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  /// Creates a [PokemonListResponse] object from a JSON map.
  factory PokemonListResponse.fromJson(Map<String, dynamic> json) {
    final List<dynamic> resultsJson = json['results'] as List<dynamic>;
    final List<Pokemon> pokemonList = resultsJson
        .map<Pokemon>(
          (dynamic item) => Pokemon.fromJson(item as Map<String, dynamic>),
        )
        .toList();

    return PokemonListResponse(
      count: json['count'] as int,
      next: json['next'] as String?,
      previous: json['previous'] as String?,
      results: pokemonList,
    );
  }
}

/// A service class for fetching Pokémon data from PokeAPI.
class PokemonApiService {
  final String _baseUrl = 'https://pokeapi.co/api/v2/pokemon';

  static const int _maxRetries = 2;
  static const Duration _retryDelay = Duration(seconds: 2);

  Future<List<Pokemon>> fetchPokemons({int offset = 0, int limit = 100}) async {
    final Uri uri = Uri.parse('$_baseUrl?offset=$offset&limit=$limit');

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final http.Response response = await http.get(uri);

        if (response.statusCode == 200) {
          final Map<String, dynamic> data =
              json.decode(response.body) as Map<String, dynamic>;
          final PokemonListResponse pokemonResponse =
              PokemonListResponse.fromJson(data);
          return pokemonResponse.results;
        } else if (response.statusCode >= 400 && response.statusCode < 500) {
          throw Exception(
            'Erro do cliente (${response.statusCode}): ${response.reasonPhrase ?? 'Requisição falhou'}',
          );
        } else if (response.statusCode >= 500) {
          if (attempt < _maxRetries) {
            await Future<void>.delayed(_retryDelay);
            continue;
          } else {
            throw Exception(
              'Erro do servidor (${response.statusCode}) após ${_maxRetries + 1} tentativas: ${response.reasonPhrase ?? 'Servidor indisponível'}',
            );
          }
        } else {
          throw Exception(
            'Resposta inesperada (${response.statusCode}): ${response.reasonPhrase ?? 'Erro desconhecido'}',
          );
        }
      } on http.ClientException catch (e) {
        if (attempt < _maxRetries) {
          await Future<void>.delayed(_retryDelay);
          continue;
        } else {
          throw Exception(
            'Erro de rede após ${_maxRetries + 1} tentativas: ${e.message}',
          );
        }
      } on FormatException {
        throw Exception('Resposta da API inválida: não é um JSON válido.');
      } catch (e) {
        throw Exception('Ocorreu um erro desconhecido: $e');
      }
    }

    throw Exception('Falha desconhecida ao carregar Pokémon.');
  }
}

/// A `ChangeNotifier` that manages the state and logic for Pokémon data.
class PokemonData extends ChangeNotifier {
  final PokemonApiService _apiService;
  List<Pokemon> _pokemons = <Pokemon>[];
  bool _isLoading = false;
  String? _errorMessage;

  PokemonData({PokemonApiService? apiService})
      : _apiService = apiService ?? PokemonApiService();

  /// The list of fetched Pokémon.
  List<Pokemon> get pokemons => _pokemons;

  /// Indicates if data is currently being fetched.
  bool get isLoading => _isLoading;

  /// An error message if fetching failed.
  String? get errorMessage => _errorMessage;

  /// Fetches Pokémon data from the API and updates the state.
  Future<void> fetchPokemons() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final List<Pokemon> fetchedPokemons = await _apiService.fetchPokemons();
      _pokemons = fetchedPokemons;
      _errorMessage = null; // Clear any previous errors on success
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _pokemons = <Pokemon>[]; // Clear pokemons on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

/// A dialog widget to display a Pokémon's image.
class PokemonImageDialog extends StatelessWidget {
  final Pokemon pokemon;

  const PokemonImageDialog({super.key, required this.pokemon});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(pokemon.name.toUpperCase()),
      content: SizedBox(
        width: 200, // Constrain dialog width for image
        height: 200, // Constrain dialog height for image
        child: Image.network(
          pokemon.imageUrl,
          fit: BoxFit.contain,
          loadingBuilder:
              (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder:
              (BuildContext context, Object exception, StackTrace? stackTrace) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.error, color: Colors.red, size: 50),
                  SizedBox(height: 8),
                  Text('Erro ao carregar imagem'),
                ],
              ),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

/// A screen to display a list of Pokémon fetched from an API.
class PokemonListScreen extends StatelessWidget {
  const PokemonListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PokemonData>(
      builder: (BuildContext context, PokemonData pokemonData, Widget? child) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: () => pokemonData.fetchPokemons(),
                icon: const Icon(Icons.refresh),
                label: const Text('Carregar Pokémon'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 20),
              if (pokemonData.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (pokemonData.errorMessage != null)
                Text(
                  'Erro: ${pokemonData.errorMessage}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium!.copyWith(color: Colors.red),
                  textAlign: TextAlign.center,
                )
              else if (pokemonData.pokemons.isEmpty)
                Text(
                  'Pressione "Carregar Pokémon" para ver a lista.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: pokemonData.pokemons.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Pokemon pokemon = pokemonData.pokemons[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ListTile(
                          leading: Text(
                            (index + 1).toString(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          title: Text(
                            pokemon.name.toUpperCase(),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () {
                            // Show the Pokémon image in a dialog
                            showDialog<void>(
                              context: context,
                              builder: (BuildContext dialogContext) {
                                return PokemonImageDialog(pokemon: pokemon);
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The root widget of the application.
///
/// It sets up the [MaterialApp] and provides the [PokemonData]
/// model using [ChangeNotifierProvider] to its descendants.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PokemonData>(
      create: (BuildContext context) => PokemonData(),
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          title: 'Aplicativo Pokémon',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Aplicativo Pokémon'),
              centerTitle: true,
            ),
            body: const PokemonListScreen(),
          ),
        );
      },
    );
  }
}

void main() => runApp(const MyApp());
