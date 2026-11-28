class LeadFilterState {
  bool mustHaveEmail;
  bool mustHavePhone;
  bool hasWebsite;
  bool hasSocial;
  String keyword;
  LeadFilterState({this.mustHaveEmail=false,this.mustHavePhone=false,this.hasWebsite=false,this.hasSocial=false,this.keyword=''});
}

class LeadEntry {
  String name; String email; String phone; String website; String social; String category; bool selected;
  LeadEntry({this.name='',this.email='',this.phone='',this.website='',this.social='',this.category='',this.selected=false});

  factory LeadEntry.fromJson(Map<String,dynamic> j)=>LeadEntry(
    name:'${j['name']??''}', email:'${j['email']??''}', phone:'${j['phone']??''}',
    website:'${j['website']??''}', social:'${j['social']??''}', category:'${j['category']??''}',
  );

  bool matches(LeadFilterState f) {
    if (f.mustHaveEmail && email.trim().isEmpty) return false;
    if (f.mustHavePhone && phone.trim().isEmpty) return false;
    if (f.hasWebsite && website.trim().isEmpty) return false;
    if (f.hasSocial && social.trim().isEmpty) return false;
    final k=f.keyword.trim().toLowerCase();
    if (k.isNotEmpty) {
      final blob='$name $email $phone $website $social $category'.toLowerCase();
      if (!blob.contains(k)) return false;
    }
    return true;
  }
}
