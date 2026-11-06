// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/ui/components/active_downloads_widget.dart';
import 'package:openlib/ui/components/page_title_widget.dart';
import 'package:openlib/ui/results_page.dart';
import 'components/snack_bar_widget.dart';

import 'package:openlib/state/state.dart'
    show
        searchAuthorProvider,
        searchPublisherProvider,
        searchQueryProvider,
        selectedTypeState,
        selectedSortState,
        selectedFileTypeState,
        selectedLanguageState,
        selectedYearState,
        typeValues,
        fileType,
        sortValues,
        languageValues,
        yearValues,
        enableFiltersState;

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _searchController;
  final TextEditingController _advancedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initialize controller with current state value
    _searchController =
        TextEditingController(text: ref.read(searchQueryProvider));

    // Keep the text field synchronized with search state changes.
    ref.listenManual(searchQueryProvider, (previous, next) {
      if (_searchController.text != next) {
        _searchController.text = next;
        // Move cursor to the end
        _searchController.selection =
            TextSelection.fromPosition(TextPosition(offset: next.length));
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _advancedController.dispose();
    super.dispose();
  }

  void _onSearchQueryChanged(String value) {
    ref.read(searchQueryProvider.notifier).state = value;
  }

  void onSubmit(BuildContext context) {
    final searchQuery = ref.read(searchQueryProvider);
    if (searchQuery.isNotEmpty) {
      ref.read(enableFiltersState.notifier).state = true;
      Navigator.push(context,
          MaterialPageRoute(builder: (BuildContext context) {
        return ResultPage(searchQuery: searchQuery);
      }));
    } else {
      showSnackBar(context: context, message: 'Search field is empty');
    }
  }

  @override
  Widget build(BuildContext context) {
    // WidgetRef is available via ConsumerState
    final dropdownTypeValue = ref.watch(selectedTypeState);
    final dropdownSortValue = ref.watch(selectedSortState);
    final dropDownFileTypeValue = ref.watch(selectedFileTypeState);
    final dropdownLanguageValue = ref.watch(selectedLanguageState);
    final dropdownYearValue = ref.watch(selectedYearState);

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Padding(
        padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const ActiveDownloadsWidget(),
            TitleText(AppLocalizations.of(context).navSearch),
            // Search Input Field
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 10),
              child: TextField(
                controller: _searchController, // <--- Added controller
                showCursor: true,
                cursorColor: Theme.of(context).colorScheme.secondary,
                decoration: InputDecoration(
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey, width: 2),
                    borderRadius: BorderRadius.all(Radius.circular(50)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.tertiary,
                        width: 2),
                    borderRadius: const BorderRadius.all(Radius.circular(50)),
                  ),
                  suffixIcon: IconButton(
                    padding: const EdgeInsets.only(right: 5),
                    color: Theme.of(context).colorScheme.secondary,
                    icon: const Icon(Icons.search, size: 23),
                    onPressed: () => onSubmit(context), // <--- Simplified call
                  ),
                  filled: true,
                  hintStyle: const TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold),
                  hintText: "Search",
                  // Remove explicit fillColor to use the theme default (Dark Grey in Dark Mode)
                ),
                onSubmitted: (String value) => onSubmit(context),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                onChanged: _onSearchQueryChanged,
              ),
            ),

            // --- Advanced Search Panel ---
            _AdvancedSearchPanel(controller: _advancedController),

            // Dropdown Filters (Unchanged)
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 250,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'Type',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_drop_down),
                  initialValue: dropdownTypeValue,
                  items: typeValues.keys
                      .toList()
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedTypeState.notifier).state = val ?? '';
                    MyLibraryDb.instance
                        .savePreference('filterType', val ?? 'All');
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 210,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'Sort by',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  initialValue: dropdownSortValue,
                  items: sortValues.keys
                      .toList()
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedSortState.notifier).state = val ?? '';
                    MyLibraryDb.instance
                        .savePreference('filterSort', val ?? 'Most Relevant');
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 165,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'File type',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  initialValue: dropDownFileTypeValue,
                  items: fileType.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedFileTypeState.notifier).state =
                        val ?? 'All';
                    MyLibraryDb.instance
                        .savePreference('filterFileType', val ?? 'All');
                  },
                ),
              ),
            ),
            // Language filter dropdown
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 200,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'Language',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  initialValue: dropdownLanguageValue,
                  items: languageValues.keys
                      .toList()
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedLanguageState.notifier).state =
                        val ?? 'All';
                    MyLibraryDb.instance
                        .savePreference('filterLanguage', val ?? 'All');
                  },
                ),
              ),
            ),
            // Year filter dropdown
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 180,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'Year Published',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  initialValue: dropdownYearValue,
                  items:
                      yearValues.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedYearState.notifier).state = val ?? 'All';
                    MyLibraryDb.instance
                        .savePreference('filterYear', val ?? 'All');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// ADVANCED SEARCH PANEL
// Expandable metadata filters: author and publisher refine the plain
// text query into field-specific terms every provider understands.
// ====================================================================

class _AdvancedSearchPanel extends ConsumerStatefulWidget {
  const _AdvancedSearchPanel({required this.controller});

  /// The main search field's controller, kept for future synergy
  /// between the plain query and the metadata fields.
  final TextEditingController controller;

  @override
  ConsumerState<_AdvancedSearchPanel> createState() =>
      _AdvancedSearchPanelState();
}

class _AdvancedSearchPanelState extends ConsumerState<_AdvancedSearchPanel> {
  bool _expanded = false;
  late final TextEditingController _authorController;
  late final TextEditingController _publisherController;

  @override
  void initState() {
    super.initState();
    _authorController =
        TextEditingController(text: ref.read(searchAuthorProvider));
    _publisherController =
        TextEditingController(text: ref.read(searchPublisherProvider));
  }

  @override
  void dispose() {
    _authorController.dispose();
    _publisherController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.secondary,
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.grey, width: 2),
        borderRadius: BorderRadius.all(Radius.circular(50)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
            color: Theme.of(context).colorScheme.tertiary, width: 2),
        borderRadius: const BorderRadius.all(Radius.circular(50)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFields = ref.watch(searchAuthorProvider).isNotEmpty ||
        ref.watch(searchPublisherProvider).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(left: 7, right: 7, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle row
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                label: Text(
                  AppLocalizations.of(context).advancedSearch,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
              if (hasActiveFields)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.filter_alt,
                    size: 14,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Column(
                children: [
                  TextField(
                    controller: _authorController,
                    decoration: _decoration(AppLocalizations.of(context).author),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                    onChanged: (value) =>
                        ref.read(searchAuthorProvider.notifier).state =
                            value.trim(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _publisherController,
                    decoration: _decoration(AppLocalizations.of(context).publisher),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                    onChanged: (value) => ref
                        .read(searchPublisherProvider.notifier)
                        .state = value.trim(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
