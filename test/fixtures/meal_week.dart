/// A cut-down copy of the eAsistent weekly meal table.
///
/// Only the structures `parseMealTable` actually keys on are kept: the
/// per-day header divs, the `ednevnik-seznam_ur_teden-td-...` cell ids, the
/// font-size-styled name div, the `div.bold` description, and the `-akcija`
/// / `span.error` status markers.
const kMealWeekHtml = '''
<div id="dijaki-prehrana-dan-2025-09-01">Ponedeljek</div>
<div id="dijaki-prehrana-dan-2025-09-02">Torek</div>
<table>
  <tr>
    <td id="ednevnik-seznam_ur_teden-td-malica-101-2025-09-01-15856">
      <div style="font-size: 11px;">Meni 1</div>
      <div class="bold">Piščančji zrezek, pire krompir (mleko)</div>
      <div id="ednevnik-seznam_ur_teden-td-malica-101-2025-09-01-15856-akcija">
        Naročen
      </div>
    </td>
    <td id="ednevnik-seznam_ur_teden-td-malica-102-2025-09-01-15856">
      <div style="font-size: 11px;">Meni 5 (XXL+0,80 EUR)</div>
      <div class="bold">Pica margarita, solata</div>
      <div id="ednevnik-seznam_ur_teden-td-malica-102-2025-09-01-15856-akcija">
        Naroči
      </div>
    </td>
    <td id="ednevnik-seznam_ur_teden-td-malica-101-2025-09-02-15856">
      <div style="font-size: 11px;">Meni 1</div>
      <div class="bold">Rižota z zelenjavo</div>
      <span class="error">Odjavljen</span>
    </td>
    <td id="ednevnik-seznam_ur_teden-td-malica-102-2025-09-02-15856">
      <div style="font-size: 11px;">Meni 5 (XXL+0,80 EUR)</div>
      <div class="bold">Golaž s polento</div>
    </td>
    <td id="ednevnik-seznam_ur_teden-td-malica-103-2025-09-02-15856">
      <div style="font-size: 11px;">Meni 3 (veg)</div>
      <div class="bold">Pica margarita, zelenjava</div>
      <div id="ednevnik-seznam_ur_teden-td-malica-103-2025-09-02-15856-akcija">
        Naroči
      </div>
    </td>
    <td id="ednevnik-seznam_ur_teden-td-malica-101-2025-09-08-15856">
      <div style="font-size: 11px;">Meni 1</div>
      <div class="bold">Iz drugega tedna</div>
    </td>
  </tr>
</table>
''';

/// The week selector, as the page renders it with week 36 active.
const kWeekSelectHtml = '''
<select id="dijaki-prehrana-teden" name="teden">
  <option value="35">31.8. - 6.9.</option>
  <option value="36" selected="selected">7.9. - 13.9.</option>
  <option value="37">14.9. - 20.9.</option>
</select>
''';
