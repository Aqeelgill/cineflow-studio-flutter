import 'package:cineflow_flutter/core/lead_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lead filters by email/phone/website/social/keyword', () {
    final leads = [
      LeadEntry(name:'A', email:'a@x.com', phone:'123', website:'https://a.com', social:'', category:'biz'),
      LeadEntry(name:'B', email:'', phone:'555', website:'', social:'https://linkedin.com/b', category:'tech'),
    ];
    final f = LeadFilterState(mustHaveEmail: true);
    expect(leads.where((l)=>l.matches(f)).length, 1);
    f..mustHaveEmail=false..hasSocial=true;
    expect(leads.where((l)=>l.matches(f)).length, 1);
    f..hasSocial=false..keyword='tech';
    expect(leads.where((l)=>l.matches(f)).map((l)=>l.name), ['B']);
  });

  test('delete selected leads removes only selected', () {
    final leads = [LeadEntry(name:'A', selected:true), LeadEntry(name:'B', selected:false), LeadEntry(name:'C', selected:true)];
    leads.removeWhere((l)=>l.selected);
    expect(leads.map((l)=>l.name).toList(), ['B']);
  });
}
