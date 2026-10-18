import 'package:flutter/material.dart';
import 'package:openlib/services/reader_fonts.dart';

Future<ReaderFont?> showReaderFontPicker(
        BuildContext context, ReaderFont current) =>
    showModalBottomSheet<ReaderFont>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReaderFontPicker(current: current),
    );

class ReaderFontPicker extends StatelessWidget {
  const ReaderFontPicker({super.key, required this.current});
  final ReaderFont current;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text('Choose font', style: TextStyle(fontSize: 20)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('10 fonts + OpenDyslexic · Available offline',
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: ReaderFonts.choices.length + 1,
                itemBuilder: (context, index) {
                  final font = index == 0
                      ? ReaderFonts.bookDefault
                      : ReaderFonts.choices[index - 1];
                  final selected = current.id == font.id;
                  return ListTile(
                    title: Text(font.name),
                    subtitle: Text(font.kind),
                    selected: selected,
                    trailing: selected ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, font),
                  );
                },
              ),
            ),
          ]),
        ),
      );
}
