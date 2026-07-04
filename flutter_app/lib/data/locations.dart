/// Country → list of states/provinces used in the profile setup screen.
/// Countries with no entry here fall back to a free-text state input.
const Map<String, List<String>> kCountryStates = {
  'India': [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
    'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand',
    'Karnataka', 'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur',
    'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Punjab',
    'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura',
    'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
    'Andaman and Nicobar Islands', 'Chandigarh', 'Dadra and Nagar Haveli and Daman and Diu',
    'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
  ],
  'United States': [
    'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado',
    'Connecticut', 'Delaware', 'District of Columbia', 'Florida', 'Georgia',
    'Hawaii', 'Idaho', 'Illinois', 'Indiana', 'Iowa', 'Kansas', 'Kentucky',
    'Louisiana', 'Maine', 'Maryland', 'Massachusetts', 'Michigan', 'Minnesota',
    'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada', 'New Hampshire',
    'New Jersey', 'New Mexico', 'New York', 'North Carolina', 'North Dakota',
    'Ohio', 'Oklahoma', 'Oregon', 'Pennsylvania', 'Rhode Island', 'South Carolina',
    'South Dakota', 'Tennessee', 'Texas', 'Utah', 'Vermont', 'Virginia',
    'Washington', 'West Virginia', 'Wisconsin', 'Wyoming',
  ],
  'United Kingdom': [
    'England', 'Scotland', 'Wales', 'Northern Ireland',
  ],
  'Canada': [
    'Alberta', 'British Columbia', 'Manitoba', 'New Brunswick',
    'Newfoundland and Labrador', 'Nova Scotia', 'Ontario',
    'Prince Edward Island', 'Quebec', 'Saskatchewan',
    'Northwest Territories', 'Nunavut', 'Yukon',
  ],
  'Australia': [
    'New South Wales', 'Victoria', 'Queensland', 'Western Australia',
    'South Australia', 'Tasmania', 'Australian Capital Territory',
    'Northern Territory',
  ],
  'Pakistan': [
    'Punjab', 'Sindh', 'Khyber Pakhtunkhwa', 'Balochistan',
    'Gilgit-Baltistan', 'Azad Kashmir', 'Islamabad Capital Territory',
  ],
  'Bangladesh': [
    'Barisal', 'Chittagong', 'Dhaka', 'Khulna',
    'Mymensingh', 'Rajshahi', 'Rangpur', 'Sylhet',
  ],
  'Nepal': [
    'Bagmati', 'Gandaki', 'Karnali', 'Koshi',
    'Lumbini', 'Madhesh', 'Sudurpashchim',
  ],
  'Sri Lanka': [
    'Central', 'Eastern', 'North Central', 'Northern',
    'North Western', 'Sabaragamuwa', 'Southern', 'Uva', 'Western',
  ],
  'United Arab Emirates': [
    'Abu Dhabi', 'Ajman', 'Dubai', 'Fujairah',
    'Ras Al Khaimah', 'Sharjah', 'Umm Al Quwain',
  ],
  'Saudi Arabia': [
    'Riyadh', 'Makkah', 'Madinah', 'Eastern Province',
    'Asir', 'Tabuk', 'Qassim', 'Hail',
    'Northern Borders', 'Jazan', 'Najran', 'Al Bahah', 'Al Jouf',
  ],
  'Germany': [
    'Baden-Württemberg', 'Bavaria', 'Berlin', 'Brandenburg', 'Bremen',
    'Hamburg', 'Hesse', 'Lower Saxony', 'Mecklenburg-Vorpommern',
    'North Rhine-Westphalia', 'Rhineland-Palatinate', 'Saarland',
    'Saxony', 'Saxony-Anhalt', 'Schleswig-Holstein', 'Thuringia',
  ],
  'France': [
    'Auvergne-Rhône-Alpes', 'Bourgogne-Franche-Comté', 'Brittany',
    'Centre-Val de Loire', 'Corsica', 'Grand Est', 'Hauts-de-France',
    'Île-de-France', 'Normandy', 'Nouvelle-Aquitaine', 'Occitanie',
    'Pays de la Loire', "Provence-Alpes-Côte d'Azur",
  ],
  'Singapore': ['Central', 'East', 'North', 'North-East', 'West'],
  'Malaysia': [
    'Johor', 'Kedah', 'Kelantan', 'Malacca', 'Negeri Sembilan',
    'Pahang', 'Penang', 'Perak', 'Perlis', 'Sabah', 'Sarawak',
    'Selangor', 'Terengganu', 'Kuala Lumpur', 'Labuan', 'Putrajaya',
  ],
  'Philippines': [
    'Metro Manila', 'Cordillera', 'Ilocos', 'Cagayan Valley',
    'Central Luzon', 'Calabarzon', 'Mimaropa', 'Bicol',
    'Western Visayas', 'Central Visayas', 'Eastern Visayas',
    'Zamboanga Peninsula', 'Northern Mindanao', 'Davao', 'Soccsksargen',
    'Caraga', 'Bangsamoro',
  ],
  'Indonesia': [
    'Jakarta', 'West Java', 'Central Java', 'East Java', 'Banten',
    'Yogyakarta', 'Bali', 'North Sumatra', 'West Sumatra', 'South Sumatra',
    'Riau', 'Lampung', 'South Sulawesi', 'North Sulawesi',
  ],
  'China': [
    'Beijing', 'Shanghai', 'Guangdong', 'Zhejiang', 'Jiangsu',
    'Shandong', 'Sichuan', 'Hubei', 'Hunan', 'Fujian', 'Henan',
  ],
  'Japan': [
    'Hokkaido', 'Tohoku', 'Kanto', 'Chubu', 'Kansai',
    'Chugoku', 'Shikoku', 'Kyushu',
  ],
  'South Korea': [
    'Seoul', 'Busan', 'Incheon', 'Daegu', 'Daejeon',
    'Gwangju', 'Ulsan', 'Sejong', 'Gyeonggi', 'Gangwon',
    'North Chungcheong', 'South Chungcheong', 'North Jeolla',
    'South Jeolla', 'North Gyeongsang', 'South Gyeongsang', 'Jeju',
  ],
  'South Africa': [
    'Eastern Cape', 'Free State', 'Gauteng', 'KwaZulu-Natal',
    'Limpopo', 'Mpumalanga', 'Northern Cape', 'North West', 'Western Cape',
  ],
  'Nigeria': [
    'Lagos', 'Abuja', 'Rivers', 'Kano', 'Oyo', 'Kaduna',
    'Delta', 'Enugu', 'Edo', 'Anambra',
  ],
  'Brazil': [
    'São Paulo', 'Rio de Janeiro', 'Minas Gerais', 'Bahia',
    'Paraná', 'Rio Grande do Sul', 'Pernambuco', 'Ceará',
    'Pará', 'Santa Catarina',
  ],
  'Other': [],
};

const List<String> kLanguages = [
  // Indian languages (most common)
  'Hindi', 'English', 'Bengali', 'Marathi', 'Telugu', 'Tamil',
  'Gujarati', 'Kannada', 'Urdu', 'Odia', 'Punjabi', 'Malayalam',
  'Assamese', 'Maithili', 'Sanskrit', 'Sindhi', 'Konkani', 'Nepali',
  'Manipuri', 'Bodo', 'Dogri', 'Kashmiri', 'Santhali', 'Bhojpuri',
  'Rajasthani', 'Haryanvi', 'Chhattisgarhi', 'Tulu',
  // International
  'Mandarin', 'Spanish', 'Arabic', 'French', 'Portuguese', 'Russian',
  'Japanese', 'German', 'Korean', 'Italian', 'Turkish', 'Vietnamese',
  'Thai', 'Indonesian', 'Dutch', 'Polish', 'Persian', 'Swahili',
  'Other',
];

const List<String> kSectors = [
  'Student',
  'Information Technology',
  'Software / IT Services',
  'Healthcare',
  'Finance / Banking',
  'Education / Teaching',
  'Government / Public Sector',
  'Engineering',
  'Manufacturing',
  'Retail / E-commerce',
  'Media / Entertainment',
  'Marketing / Advertising',
  'Sales / Business Development',
  'Legal',
  'Real Estate',
  'Hospitality / Tourism',
  'Agriculture',
  'Transportation / Logistics',
  'Construction',
  'Telecommunications',
  'Energy / Utilities',
  'Consulting',
  'Non-Profit',
  'Freelance / Self-employed',
  'Unemployed',
  'Other',
];
