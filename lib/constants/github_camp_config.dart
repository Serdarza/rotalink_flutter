/// GitHub — kamp alanları (`data/camp_sites.json`).
abstract final class GithubCampConfig {
  static const fileName = 'camp_sites.json';

  static final uri = Uri.parse(
    'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/data/camp_sites.json',
  );
}
