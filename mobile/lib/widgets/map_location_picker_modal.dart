import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LocationResult {
  final String displayName;
  final String shortName;
  final double latitude;
  final double longitude;

  const LocationResult({
    required this.displayName,
    required this.shortName,
    required this.latitude,
    required this.longitude,
  });
}

class MapLocationPickerModal extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialName;

  const MapLocationPickerModal({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialName,
  });

  static Future<LocationResult?> mostra(
    BuildContext context, {
    double? initialLat,
    double? initialLng,
    String? initialName,
  }) {
    return showModalBottomSheet<LocationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (ctx) => MapLocationPickerModal(
        initialLat: initialLat,
        initialLng: initialLng,
        initialName: initialName,
      ),
    );
  }

  @override
  State<MapLocationPickerModal> createState() => _MapLocationPickerModalState();
}

class _MapLocationPickerModalState extends State<MapLocationPickerModal> {
  late final MapController _mapController;
  late LatLng _selectedLocation;
  final TextEditingController _searchController = TextEditingController();

  bool _isSearching = false;
  bool _isReverseGeocoding = false;
  bool _isLocating = false;
  Timer? _debounceTimer;

  List<Map<String, dynamic>> _searchResults = [];

  String _currentPlaceName = 'Caricamento posizione...';
  String _currentAddress = '';

  // Default coordinate: Roma Centro se non fornite
  static const LatLng _defaultRome = LatLng(41.9028, 12.4964);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    if (widget.initialLat != null && widget.initialLng != null) {
      _selectedLocation = LatLng(widget.initialLat!, widget.initialLng!);
      _currentPlaceName = widget.initialName?.isNotEmpty == true
          ? widget.initialName!
          : 'Punto Selezionato';
      _currentAddress = 'Lat: ${widget.initialLat!.toStringAsFixed(4)}, Lon: ${widget.initialLng!.toStringAsFixed(4)}';
      _reverseGeocode(_selectedLocation);
    } else {
      _selectedLocation = _defaultRome;
      _currentPlaceName = 'Roma Centro';
      _currentAddress = 'Tocca la mappa o cerca per scegliere un luogo';
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    final clean = val.trim();
    if (clean.length < 3) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    // Debounce di 380ms per evitare flood di richieste al server
    _debounceTimer = Timer(const Duration(milliseconds: 380), () {
      _eseguiRicerca(clean);
    });
  }

  Future<void> _eseguiRicerca(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    List<Map<String, dynamic>> risultati = [];

    // 1. Tenta prima con Photon API (Komoot OpenStreetMap index: rapidissimo, senza rate limit 429)
    try {
      final photonUri = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(cleanQuery)}&lang=it&limit=8',
      );
      final response = await http.get(photonUri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> features = data['features'] ?? [];

        for (var f in features) {
          final props = f['properties'] as Map<String, dynamic>? ?? {};
          final geom = f['geometry'] as Map<String, dynamic>? ?? {};
          final coords = geom['coordinates'] as List<dynamic>? ?? [];

          if (coords.length >= 2) {
            final double lon = (coords[0] as num).toDouble();
            final double lat = (coords[1] as num).toDouble();

            final String name = (props['name'] ?? props['street'] ?? '').toString();
            final String street = (props['street'] ?? '').toString();
            final String housenumber = (props['housenumber'] ?? '').toString();
            final String city = (props['city'] ?? props['town'] ?? props['village'] ?? props['county'] ?? '').toString();
            final String state = (props['state'] ?? '').toString();
            final String postcode = (props['postcode'] ?? '').toString();

            final List<String> addressParts = [];
            if (street.isNotEmpty) {
              addressParts.add(housenumber.isNotEmpty ? '$street $housenumber' : street);
            } else if (name.isNotEmpty) {
              addressParts.add(name);
            }
            if (postcode.isNotEmpty && city.isNotEmpty) {
              addressParts.add('$postcode $city');
            } else if (city.isNotEmpty) {
              addressParts.add(city);
            }
            if (state.isNotEmpty && state != city) {
              addressParts.add(state);
            }
            addressParts.add('Italia');

            final fullAddress = addressParts.join(', ');
            final title = name.isNotEmpty ? name : (street.isNotEmpty ? street : city);

            risultati.add({
              'lat': lat,
              'lon': lon,
              'title': title.isNotEmpty ? title : fullAddress,
              'display_name': fullAddress,
            });
          }
        }
      }
    } catch (_) {}

    // 2. Se Photon non ha trovato nulla o ha fallito, prova Nominatim con fallback
    if (risultati.isEmpty) {
      try {
        final nominatimUri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(cleanQuery)}&format=json&addressdetails=1&limit=6&accept-language=it',
        );
        final response = await http.get(nominatimUri, headers: {
          'User-Agent': 'FantaEventiApp/2.0 (mobile-app)',
        }).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          for (var item in data) {
            final lat = double.tryParse(item['lat']?.toString() ?? '');
            final lon = double.tryParse(item['lon']?.toString() ?? '');
            if (lat != null && lon != null) {
              final disp = (item['display_name'] ?? '').toString();
              final name = (item['name'] ?? '').toString();
              final title = name.isNotEmpty ? name : disp.split(',').first.trim();
              risultati.add({
                'lat': lat,
                'lon': lon,
                'title': title,
                'display_name': disp,
              });
            }
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _searchResults = risultati;
        _isSearching = false;
      });
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() {
      _isReverseGeocoding = true;
    });

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json&addressdetails=1&accept-language=it',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'FantaEventiApp/2.0 (mobile-app)',
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final displayName = (data['display_name'] ?? '').toString();
        final address = data['address'] as Map<String, dynamic>?;

        String shortName = '';
        if (address != null) {
          shortName = address['amenity'] ??
              address['leisure'] ??
              address['building'] ??
              address['road'] ??
              address['suburb'] ??
              address['city'] ??
              address['town'] ??
              address['village'] ??
              '';
        }
        if (shortName.isEmpty) {
          final parts = displayName.split(',');
          shortName = parts.isNotEmpty ? parts.first.trim() : 'Luogo Selezionato';
        }

        if (mounted) {
          setState(() {
            _currentPlaceName = shortName;
            _currentAddress = displayName;
            _isReverseGeocoding = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentPlaceName = 'Punto Mappa (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
            _currentAddress = 'Coordinate salvate';
            _isReverseGeocoding = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _currentPlaceName = 'Punto Mappa (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
          _currentAddress = 'Coordinate salvate';
          _isReverseGeocoding = false;
        });
      }
    }
  }

  Future<void> _vaiAllaMiaPosizione() async {
    setState(() {
      _isLocating = true;
    });

    try {
      // 1. Controllo se i servizi di localizzazione sono attivi
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFDC2626),
              content: Text(
                'Attiva il GPS del telefono per rilevare la tua posizione 📍',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _isLocating = false);
        return;
      }

      // 2. Controllo e richiesta permessi
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFFDC2626),
                content: Text(
                  'Permesso di localizzazione negato.',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          setState(() => _isLocating = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFDC2626),
              content: Text(
                'Permesso GPS negato permanentemente. Abilitalo dalle impostazioni.',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _isLocating = false);
        return;
      }

      // 3. Rileva la posizione GPS ad alta precisione
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final userLatLng = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _selectedLocation = userLatLng;
          _searchResults = [];
          _searchController.clear();
        });
        _mapController.move(userLatLng, 16.5);
        await _reverseGeocode(userLatLng);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(
              'Impossibile rilevare la posizione GPS in questo momento.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _selezionaRisultato(Map<String, dynamic> item) {
    final lat = double.tryParse(item['lat']?.toString() ?? '') ?? _selectedLocation.latitude;
    final lon = double.tryParse(item['lon']?.toString() ?? '') ?? _selectedLocation.longitude;
    final newPos = LatLng(lat, lon);

    final displayName = item['display_name']?.toString() ?? '';
    final title = item['title']?.toString() ?? displayName.split(',').first.trim();

    setState(() {
      _selectedLocation = newPos;
      _currentPlaceName = title;
      _currentAddress = displayName;
      _searchResults = [];
      _searchController.text = title;
    });

    _mapController.move(newPos, 16.0);
    FocusScope.of(context).unfocus();
  }

  void _onTapMappa(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
      _searchResults = [];
    });
    _reverseGeocode(point);
  }

  void _conferma() {
    Navigator.of(context).pop(
      LocationResult(
        displayName: _currentAddress.isNotEmpty ? _currentAddress : _currentPlaceName,
        shortName: _currentPlaceName,
        latitude: _selectedLocation.latitude,
        longitude: _selectedLocation.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final height = mediaQuery.size.height * 0.90;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            // Handle superiore
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            // Header con Titolo e Chiudi
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.map_rounded, color: Color(0xFFFACC15), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scegli il Luogo sulla Mappa',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Cerca o tocca un punto qualsiasi per posizionare il pin',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),

            // Barra di Ricerca
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                onSubmitted: (val) {
                  _debounceTimer?.cancel();
                  _eseguiRicerca(val);
                },
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Cerca via, piazza, locale, pub o città...',
                  hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                  prefixIcon: IconButton(
                    icon: const Icon(Icons.search_rounded, color: Color(0xFFFACC15)),
                    onPressed: () {
                      _debounceTimer?.cancel();
                      _eseguiRicerca(_searchController.text);
                    },
                  ),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFACC15)),
                          ),
                        )
                      : _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 18),
                              onPressed: () {
                                _debounceTimer?.cancel();
                                _searchController.clear();
                                setState(() => _searchResults = []);
                              },
                            )
                          : null,
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFFACC15), width: 1.5),
                  ),
                ),
              ),
            ),

            // Contenitore Mappa + Risultati di Ricerca sovrapposti
            Expanded(
              child: Stack(
                children: [
                  // MAPPA FLUTTER_MAP
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _selectedLocation,
                      initialZoom: 14.5,
                      minZoom: 4,
                      maxZoom: 18.5,
                      onTap: _onTapMappa,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.fantaeventi.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedLocation,
                            width: 50,
                            height: 50,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFFDC2626),
                              size: 46,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Overlay Risultati di Ricerca (se presenti)
                  if (_searchResults.isNotEmpty)
                    Positioned(
                      top: 4,
                      left: 16,
                      right: 16,
                      child: Material(
                        elevation: 10,
                        borderRadius: BorderRadius.circular(14),
                        color: const Color(0xFF1E293B),
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 250),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.5)),
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, i) => const Divider(color: Color(0xFF334155), height: 1),
                            itemBuilder: (ctx, i) {
                              final item = _searchResults[i];
                              final title = (item['title'] ?? '').toString();
                              final sub = (item['display_name'] ?? '').toString();

                              return ListTile(
                                visualDensity: VisualDensity.compact,
                                leading: const Icon(Icons.place_rounded, color: Color(0xFFFACC15), size: 20),
                                title: Text(
                                  title,
                                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  sub,
                                  style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _selezionaRisultato(item),
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                  // Pulsanti Fluttuanti: GPS Posizione Live + Zoom
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pulsante GPS: La mia posizione in tempo reale
                        FloatingActionButton.small(
                          heroTag: 'my_gps_location_btn',
                          backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.95),
                          foregroundColor: const Color(0xFFFACC15),
                          tooltip: 'La mia posizione GPS',
                          onPressed: _isLocating ? null : _vaiAllaMiaPosizione,
                          child: _isLocating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFACC15)),
                                )
                              : const Icon(Icons.my_location_rounded, size: 20),
                        ),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                          heroTag: 'zoom_in_map',
                          backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.85),
                          foregroundColor: const Color(0xFFFACC15),
                          onPressed: () {
                            final cur = _mapController.camera.zoom;
                            _mapController.move(_selectedLocation, (cur + 1).clamp(4, 18.5));
                          },
                          child: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'zoom_out_map',
                          backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.85),
                          foregroundColor: const Color(0xFFFACC15),
                          onPressed: () {
                            final cur = _mapController.camera.zoom;
                            _mapController.move(_selectedLocation, (cur - 1).clamp(4, 18.5));
                          },
                          child: const Icon(Icons.remove),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scheda Luogo Selezionato + Pulsante di Conferma
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _isReverseGeocoding
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFACC15)),
                                )
                              : const Icon(Icons.place_rounded, color: Color(0xFFFACC15), size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentPlaceName,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _currentAddress.isNotEmpty
                                    ? _currentAddress
                                    : 'Lat: ${_selectedLocation.latitude.toStringAsFixed(4)}, Lon: ${_selectedLocation.longitude.toStringAsFixed(4)}',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _conferma,
                        icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF0F172A)),
                        label: Text(
                          'CONFERMA QUESTO LUOGO',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFACC15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
