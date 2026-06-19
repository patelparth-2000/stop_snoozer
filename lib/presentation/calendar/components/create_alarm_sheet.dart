import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/commute_alarm.dart';
import '../../../data/models/stop_point.dart';
import '../../../data/models/trip_group.dart';
import '../../../data/models/trip_leg.dart';
import '../../../data/repositories/stop_points_repository.dart';
import '../../../data/repositories/trip_groups_repository.dart';
import '../../../data/services/postcode_geocoder.dart';
import '../../../core/constants/app_constants.dart';
import '../calendar_viewmodel.dart';

class CreateAlarmSheet extends StatefulWidget {
  const CreateAlarmSheet({super.key, this.initialAlarm});
  final CommuteAlarm? initialAlarm;

  @override
  State<CreateAlarmSheet> createState() => _CreateAlarmSheetState();
}

class _CreateAlarmSheetState extends State<CreateAlarmSheet> {
  // ── Form state ─────────────────────────────────────────────────────────────
  late TimeOfDay _time;
  StopPoint? _stop;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _searchCtrl;
  late Set<int> _days;
  late bool _oneOff;
  DateTime? _oneOffDate;

  // ── Group-mode state ───────────────────────────────────────────────────────
  bool _useGroup             = false;
  TripGroup? _selectedGroup;
  List<TripGroup> _savedGroups = [];

  // ── Search state ───────────────────────────────────────────────────────────
  List<StopPoint> _results   = [];
  bool _searching            = false;
  bool _isPostcodeMode       = false;
  Timer? _debounce;
  final _repo                = StopPointsRepository();

  // ── New-group creation state ──────────────────────────────────────────────
  bool _creatingNewGroup             = false;
  final _newGroupNameCtrl            = TextEditingController();
  final _newGroupSearchCtrl          = TextEditingController();
  List<StopPoint> _newGroupStops     = [];
  List<StopPoint> _newGroupResults   = [];
  bool _newGroupSearching            = false;
  Timer? _newGroupDebounce;

  // ── Design tokens ─────────────────────────────────────────────────────────
  static const _bg     = Color(0xFF0B0F19);
  static const _card   = Color(0xFF1E293B);
  static const _amber  = Color(0xFFFFB000);
  static const _slate  = Color(0xFFE2E8F0);
  static const _muted  = Color(0xFF64748B);
  static const _border = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
    final a = widget.initialAlarm;
    if (a != null) {
      _useGroup  = a.tripGroupId != null;
      _time      = TimeOfDay(hour: a.departureHour, minute: a.departureMinute);
      _labelCtrl = TextEditingController(text: a.routeLabel);
      _searchCtrl = TextEditingController(text: _useGroup ? '' : a.stopName);
      _days      = a.weekdays.toSet();
      _oneOff    = a.specificDate != null;
      if (a.specificDate != null) {
        try { _oneOffDate = DateTime.parse(a.specificDate!); } catch (_) {}
      }
      if (!_useGroup) {
        _stop = StopPoint(
          id:        a.stopId,
          name:      a.stopName,
          latitude:  a.lat,
          longitude: a.lon,
          mode:      TransitMode.bus,
          wifiSsid:  a.wifiSsid,
        );
      }
    } else {
      _time       = TimeOfDay.now();
      _labelCtrl  = TextEditingController();
      _searchCtrl = TextEditingController();
      _days       = {};
      _oneOff     = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGroups());
  }

  Future<void> _loadGroups() async {
    final groups = await TripGroupsRepository.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _savedGroups = groups;
      final editId = widget.initialAlarm?.tripGroupId;
      if (editId != null) {
        _selectedGroup = groups.where((g) => g.id == editId).firstOrNull;
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _newGroupDebounce?.cancel();
    _labelCtrl.dispose();
    _searchCtrl.dispose();
    _newGroupNameCtrl.dispose();
    _newGroupSearchCtrl.dispose();
    super.dispose();
  }

  // ── Search logic ───────────────────────────────────────────────────────────

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _results = []; _searching = false; _isPostcodeMode = false; });
      return;
    }
    final isPostcode = PostcodeGeocoder.isPostcode(q);
    setState(() { _searching = true; _isPostcodeMode = isPostcode; });
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      List<StopPoint> results;
      if (isPostcode) {
        results = await _repo.postcodeSearch(q.trim()) ?? [];
      } else {
        results = await _repo.search(q.trim());
        results.sort((a, b) => _modePriority(a.mode).compareTo(_modePriority(b.mode)));
      }
      if (mounted) setState(() { _results = results.take(8).toList(); _searching = false; });
    });
  }

  // ── New group creation ─────────────────────────────────────────────────────

  void _onNewGroupSearchChanged(String q) {
    _newGroupDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _newGroupResults = []; _newGroupSearching = false; });
      return;
    }
    setState(() => _newGroupSearching = true);
    _newGroupDebounce = Timer(const Duration(milliseconds: 400), () async {
      final results = await _repo.search(q.trim());
      results.sort((a, b) => _modePriority(a.mode).compareTo(_modePriority(b.mode)));
      if (mounted) setState(() { _newGroupResults = results.take(6).toList(); _newGroupSearching = false; });
    });
  }

  void _addStopToNewGroup(StopPoint stop) {
    setState(() {
      _newGroupStops   = [..._newGroupStops, stop];
      _newGroupResults = [];
      _newGroupSearchCtrl.clear();
    });
    FocusScope.of(context).unfocus();
  }

  void _removeStopFromNewGroup(int i) {
    final stops = [..._newGroupStops]..removeAt(i);
    setState(() => _newGroupStops = stops);
  }

  Future<void> _saveNewGroup() async {
    if (_newGroupStops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one stop to the group.')),
      );
      return;
    }
    final name = _newGroupNameCtrl.text.trim().isEmpty
        ? 'Group ${_savedGroups.length + 1}'
        : _newGroupNameCtrl.text.trim();
    final legs  = _newGroupStops.map((s) => TripLeg(stop: s)).toList();
    final group = TripGroup(
      id:   DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      legs: legs,
    );
    await TripGroupsRepository.instance.save(group);
    if (!mounted) return;
    setState(() {
      _savedGroups      = [..._savedGroups, group];
      _selectedGroup    = group;
      _creatingNewGroup = false;
      _newGroupStops    = [];
      _newGroupResults  = [];
      _newGroupNameCtrl.clear();
      _newGroupSearchCtrl.clear();
      if (_labelCtrl.text.isEmpty) _labelCtrl.text = name;
    });
  }

  static int _modePriority(TransitMode m) {
    switch (m) {
      case TransitMode.tube:
      case TransitMode.dlr:
      case TransitMode.overground:
      case TransitMode.rail:
        return 0;
      case TransitMode.tram:
        return 1;
      default:
        return 2;
    }
  }

  void _selectStop(StopPoint stop) {
    setState(() {
      _stop    = stop;
      _results = [];
      _searchCtrl.text = stop.name;
      if (_labelCtrl.text.isEmpty) {
        _labelCtrl.text = stop.name;
      }
    });
    FocusScope.of(context).unfocus();
  }

  // ── Time picker ────────────────────────────────────────────────────────────
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary:    Color(0xFFFFB000),
            onPrimary:  Color(0xFF0B0F19),
            surface:    Color(0xFF1E293B),
            onSurface:  Color(0xFFE2E8F0),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  // ── Date picker ────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _oneOffDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary:   Color(0xFFFFB000),
            onPrimary: Color(0xFF0B0F19),
            surface:   Color(0xFF1E293B),
            onSurface: Color(0xFFE2E8F0),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _oneOffDate = picked);
  }

  // ── Save ───────────────────────────────────────────────────────────────────
  void _save() {
    // Determine effective stop (single stop or first leg of a group)
    StopPoint? effectiveStop;
    String? effectiveGroupId;

    if (_useGroup) {
      if (_selectedGroup == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a trip group.')),
        );
        return;
      }
      if (_selectedGroup!.legs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected group has no stops.')),
        );
        return;
      }
      effectiveStop    = _selectedGroup!.legs.first.stop;
      effectiveGroupId = _selectedGroup!.id;
    } else {
      if (_stop == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a destination stop.')),
        );
        return;
      }
      effectiveStop = _stop!;
    }

    if (!_oneOff && _days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one day.')),
      );
      return;
    }
    if (_oneOff && _oneOffDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a date for the one-off alarm.')),
      );
      return;
    }

    final defaultLabel = _useGroup ? _selectedGroup!.name : effectiveStop.name;
    final label = _labelCtrl.text.trim().isEmpty ? defaultLabel : _labelCtrl.text.trim();

    final specDate = _oneOff && _oneOffDate != null
        ? '${_oneOffDate!.year.toString().padLeft(4, '0')}'
          '-${_oneOffDate!.month.toString().padLeft(2, '0')}'
          '-${_oneOffDate!.day.toString().padLeft(2, '0')}'
        : null;

    final initial = widget.initialAlarm;
    final alarm = CommuteAlarm(
      id:              initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      departureHour:   _time.hour,
      departureMinute: _time.minute,
      stopId:          effectiveStop.id,
      stopName:        effectiveStop.name,
      transitMode:     effectiveStop.transitTypeString,
      routeLabel:      label,
      weekdays:        _oneOff ? [] : _days.toList()..sort(),
      lat:             effectiveStop.latitude,
      lon:             effectiveStop.longitude,
      wifiSsid:        effectiveStop.wifiSsid,
      specificDate:    specDate,
      isActive:        initial?.isActive ?? true,
      tripGroupId:     effectiveGroupId,
    );

    final cubit = context.read<CommuteAlarmsCubit>();
    if (initial != null) {
      cubit.updateAlarm(alarm);
    } else {
      cubit.add(alarm);
    }
    Navigator.of(context).pop();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight      = MediaQuery.of(context).size.height * 0.92;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border, width: 1)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + keyboardHeight),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Handle + title ─────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'New Commute Alarm',
              style: GoogleFonts.sora(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _slate,
              ),
            ),
            const SizedBox(height: 24),

            // ── Departure time ─────────────────────────────────────────
            _SectionLabel('Departure Time'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded, color: _amber, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      _formatTime(_time),
                      style: GoogleFonts.sora(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _slate,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Destination stop ───────────────────────────────────────
            _SectionLabel('Destination'),
            const SizedBox(height: 8),

            // Mode toggle: Single Stop ↔ Trip Group
            Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() { _useGroup = false; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_useGroup ? _amber.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd - 1),
                        border: !_useGroup ? Border.all(color: _amber.withValues(alpha: 0.6)) : null,
                      ),
                      child: Center(child: Text('Single Stop',
                          style: GoogleFonts.sora(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: !_useGroup ? _amber : _muted))),
                    ),
                  )),
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() { _useGroup = true; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _useGroup ? _amber.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd - 1),
                        border: _useGroup ? Border.all(color: _amber.withValues(alpha: 0.6)) : null,
                      ),
                      child: Center(child: Text('Trip Group',
                          style: GoogleFonts.sora(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: _useGroup ? _amber : _muted))),
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (!_useGroup) ...[
              _StopSearchField(
                controller: _searchCtrl,
                isSearching: _searching,
                isPostcodeMode: _isPostcodeMode,
                selectedStop: _stop,
                results: _results,
                onChanged: _onSearchChanged,
                onSelect: _selectStop,
                onClear: () => setState(() {
                  _stop = null;
                  _searchCtrl.clear();
                  _results = [];
                  _isPostcodeMode = false;
                }),
              ),
            ] else ...[
              // ── Existing groups list ─────────────────────────────────────
              if (_savedGroups.isNotEmpty && !_creatingNewGroup)
                Column(
                  children: _savedGroups.map((g) {
                    final selected = _selectedGroup?.id == g.id;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedGroup = g;
                        if (_labelCtrl.text.isEmpty) _labelCtrl.text = g.name;
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: selected ? _amber.withValues(alpha: 0.12) : _card,
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          border: Border.all(
                            color: selected ? _amber.withValues(alpha: 0.7) : _border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.route_rounded, color: selected ? _amber : _muted, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g.name, style: GoogleFonts.sora(
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                    color: selected ? _amber : _slate)),
                                Text('${g.legs.length} stop${g.legs.length == 1 ? '' : 's'}',
                                    style: GoogleFonts.inter(fontSize: 11, color: _muted)),
                              ],
                            )),
                            if (selected)
                              const Icon(Icons.check_circle_rounded, color: _amber, size: 18),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // ── Inline group builder ─────────────────────────────────────
              if (_creatingNewGroup) ...[
                TextField(
                  controller: _newGroupNameCtrl,
                  style: GoogleFonts.inter(fontSize: 13, color: _slate),
                  decoration: InputDecoration(
                    hintText: 'Group name…',
                    hintStyle: GoogleFonts.inter(fontSize: 12, color: _muted),
                    prefixIcon: const Icon(Icons.label_outline_rounded, color: _muted, size: 18),
                    filled: true, fillColor: _card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd), borderSide: const BorderSide(color: _border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd), borderSide: const BorderSide(color: _border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd), borderSide: const BorderSide(color: _amber, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 8),
                _StopSearchField(
                  controller: _newGroupSearchCtrl,
                  isSearching: _newGroupSearching,
                  isPostcodeMode: false,
                  selectedStop: null,
                  results: _newGroupResults,
                  hintText: 'Add a stop…',
                  onChanged: _onNewGroupSearchChanged,
                  onSelect: _addStopToNewGroup,
                  onClear: () {},
                ),
                if (_newGroupStops.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._newGroupStops.asMap().entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        Text('${e.key + 1}', style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w700, color: _amber)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.value.name, style: GoogleFonts.inter(fontSize: 12, color: _slate), overflow: TextOverflow.ellipsis)),
                        GestureDetector(
                          onTap: () => _removeStopFromNewGroup(e.key),
                          child: const Icon(Icons.close_rounded, color: _muted, size: 16),
                        ),
                      ],
                    ),
                  )),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _creatingNewGroup = false;
                          _newGroupStops    = [];
                          _newGroupResults  = [];
                          _newGroupNameCtrl.clear();
                          _newGroupSearchCtrl.clear();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                            border: Border.all(color: _border),
                          ),
                          child: Center(child: Text('Cancel', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _muted))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: _saveNewGroup,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                            border: Border.all(color: _amber.withValues(alpha: 0.6)),
                          ),
                          child: Center(child: Text('Save Group', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: _amber))),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else
                // ── + New Group button ──────────────────────────────────────
                GestureDetector(
                  onTap: () => setState(() => _creatingNewGroup = true),
                  child: Container(
                    margin: EdgeInsets.only(top: _savedGroups.isEmpty ? 0 : 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                      border: Border.all(color: _amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_circle_outline_rounded, color: _amber, size: 16),
                        const SizedBox(width: 6),
                        Text('New Group', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: _amber)),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 20),

            // ── Route label ────────────────────────────────────────────
            _SectionLabel('Route Label'),
            const SizedBox(height: 8),
            TextField(
              controller: _labelCtrl,
              style: GoogleFonts.inter(fontSize: 14, color: _slate),
              decoration: InputDecoration(
                hintText: 'e.g. Office via Northern Line',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: _muted),
                filled: true,
                fillColor: _card,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  borderSide: const BorderSide(color: _amber, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Schedule ───────────────────────────────────────────────
            _SectionLabel('Schedule'),
            const SizedBox(height: 8),

            // One-time date row (shown when Repeat is OFF)
            if (_oneOff)
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: _amber, size: 18),
                      const SizedBox(width: 12),
                      Text(
                        _oneOffDate == null
                            ? 'Pick a date…'
                            : _formatDate(_oneOffDate!),
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _oneOffDate == null ? _muted : _slate,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Repeat toggle row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.repeat_rounded, color: _amber, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    'Repeat weekly',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: _slate,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: !_oneOff,
                    activeThumbColor: _amber,
                    activeTrackColor: _amber.withValues(alpha: 0.4),
                    onChanged: (on) => setState(() {
                      _oneOff = !on;
                      if (on && _days.isEmpty) _days = {1, 2, 3, 4, 5};
                    }),
                  ),
                ],
              ),
            ),

            // Weekday chips (shown when Repeat is ON)
            if (!_oneOff) ...[
              const SizedBox(height: 10),
              _WeekdayChipRow(
                selected: _days,
                onToggle: (d) => setState(() {
                  if (_days.contains(d)) {
                    _days.remove(d);
                  } else {
                    _days.add(d);
                  }
                }),
              ),
            ],

            const SizedBox(height: 28),

            // ── Save ───────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _amber,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Center(
                    child: Text(
                      'Save Alarm',
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0B0F19),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  String _formatTime(TimeOfDay t) {
    final h12 = t.hour == 0 ? 12 : t.hour > 12 ? t.hour - 12 : t.hour;
    final amPm = t.hour < 12 ? 'AM' : 'PM';
    return '${h12.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $amPm';
  }

  String _formatDate(DateTime d) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }
}

// ── Stop search field ──────────────────────────────────────────────────────

class _StopSearchField extends StatelessWidget {
  const _StopSearchField({
    required this.controller,
    required this.isSearching,
    required this.isPostcodeMode,
    required this.selectedStop,
    required this.results,
    required this.onChanged,
    required this.onSelect,
    required this.onClear,
    this.hintText = 'Stop name or postcode…',
  });

  final TextEditingController controller;
  final bool isSearching;
  final bool isPostcodeMode;
  final StopPoint? selectedStop;
  final List<StopPoint> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<StopPoint> onSelect;
  final VoidCallback onClear;
  final String hintText;

  static const _card   = Color(0xFF1E293B);
  static const _amber  = Color(0xFFFFB000);
  static const _slate  = Color(0xFFE2E8F0);
  static const _muted  = Color(0xFF64748B);
  static const _border = Color(0xFF334155);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: GoogleFonts.inter(fontSize: 14, color: _slate),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.inter(fontSize: 13, color: _muted),
            prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 20),
            suffixIcon: selectedStop != null
                ? GestureDetector(
                    onTap: onClear,
                    child: const Icon(Icons.close_rounded, color: _muted, size: 18),
                  )
                : isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: _amber),
                        ),
                      )
                    : null,
            filled: true,
            fillColor: _card,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              borderSide: BorderSide(
                color: selectedStop != null
                    ? _amber.withValues(alpha: 0.6)
                    : _border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              borderSide: const BorderSide(color: _amber, width: 1.5),
            ),
          ),
        ),
        if (isPostcodeMode) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              border: Border.all(color: _amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: _amber, size: 14),
                const SizedBox(width: 6),
                Text('Showing stops near postcode',
                    style: GoogleFonts.inter(fontSize: 11, color: _amber, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
        if (results.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: results.map((s) {
                final isLast = s == results.last;
                return Column(
                  children: [
                    InkWell(
                      onTap: () => onSelect(s),
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Text(
                              _modeEmoji(s.mode),
                              style: const TextStyle(fontSize: 15),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    s.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: _slate,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (s.indicator != null)
                                    Text(
                                      s.indicator!,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: _muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast)
                      const Divider(height: 1, color: _border),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  String _modeEmoji(TransitMode m) {
    switch (m) {
      case TransitMode.tube:       return '🚇';
      case TransitMode.dlr:        return '🚈';
      case TransitMode.overground: return '🚆';
      case TransitMode.tram:       return '🚊';
      case TransitMode.rail:       return '🚂';
      case TransitMode.ferry:      return '⛴';
      case TransitMode.bus:        return '🚌';
    }
  }
}

// ── Weekday chip row ───────────────────────────────────────────────────────

class _WeekdayChipRow extends StatelessWidget {
  const _WeekdayChipRow({
    required this.selected,
    required this.onToggle,
  });

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  static const _days = [
    (day: 1, label: 'M'),
    (day: 2, label: 'T'),
    (day: 3, label: 'W'),
    (day: 4, label: 'Th'),
    (day: 5, label: 'F'),
    (day: 6, label: 'Sa'),
    (day: 7, label: 'Su'),
  ];

  static const _amber  = Color(0xFFFFB000);
  static const _border = Color(0xFF334155);
  static const _muted  = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _days.map((d) {
        final active = selected.contains(d.day);
        return Expanded(
          child: GestureDetector(
            onTap: () => onToggle(d.day),
            child: Container(
              margin: const EdgeInsets.only(right: 5),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: active
                    ? _amber.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusSm),
                border: Border.all(
                  color: active
                      ? _amber.withValues(alpha: 0.7)
                      : _border,
                ),
              ),
              child: Center(
                child: Text(
                  d.label,
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? _amber : _muted,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: GoogleFonts.sora(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF64748B),
          letterSpacing: 0.15,
        ),
      );
}
