import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/places_service.dart';

class PlacesAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final Function(PlacePrediction)? onPlaceSelected;
  final Function(bool)? onSuggestionsChanged;
  final bool isLoading;

  const PlacesAutocompleteField({
    super.key,
    required this.controller,
    this.hintText = 'Ingresa tu destino',
    this.onPlaceSelected,
    this.onSuggestionsChanged,
    this.isLoading = false,
  });

  @override
  State<PlacesAutocompleteField> createState() => _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
  List<PlacePrediction> _predictions = [];
  bool _isSearching = false;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    if (text.length >= 2) {
      _searchPlaces(text);
    } else {
      _updateSuggestions([], false);
    }
  }

  Future<void> _searchPlaces(String query) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final predictions = await PlacesService.getPlacePredictions(query);
      _updateSuggestions(predictions, predictions.isNotEmpty);
      setState(() {
        _isSearching = false;
      });
    } catch (e) {
      _updateSuggestions([], false);
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _updateSuggestions(List<PlacePrediction> predictions, bool show) {
    setState(() {
      _predictions = predictions;
      _showSuggestions = show;
    });
    // Notificar al widget padre sobre el cambio en las sugerencias
    widget.onSuggestionsChanged?.call(show);
  }

  void _onPlaceTap(PlacePrediction prediction) {
    // Feedback táctil inmediato
    HapticFeedback.lightImpact();
    
    // Actualizar el texto del campo
    widget.controller.text = prediction.description;
    
    // Ocultar sugerencias inmediatamente para mejor UX
    _updateSuggestions([], false);
    
    // Pequeño delay para que el usuario vea la selección
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onPlaceSelected?.call(prediction);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: widget.controller,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(color: Colors.grey.shade600),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF0A1639)),
            ),
            prefixIcon: const Icon(Icons.location_on, color: Color(0xFF0A1639)),
            suffixIcon: (_isSearching || widget.isLoading)
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A1639)),
                      ),
                    ),
                  )
                : null,
          ),
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF0A0A0A),
          ),
          onTap: () {
            if (_predictions.isNotEmpty) {
              setState(() {
                _showSuggestions = true;
              });
            }
          },
        ),
        // Animación suave para mostrar/ocultar sugerencias
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: _showSuggestions && _predictions.isNotEmpty ? null : 0,
          child: _showSuggestions && _predictions.isNotEmpty
              ? Container(
                  margin: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _predictions.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: Colors.grey.shade200,
                      ),
                      itemBuilder: (context, index) {
                        final prediction = _predictions[index];
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _onPlaceTap(prediction),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Color(0xFF0A1639),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prediction.mainText,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF0A0A0A),
                                          ),
                                        ),
                                        if (prediction.secondaryText.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              prediction.secondaryText,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}