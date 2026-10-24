import Foundation

/// Inglês ou português, conforme a língua do iPhone (por agora só estas duas).
func L(_ en: String, _ pt: String) -> String {
    Locale.preferredLanguages.first?.lowercased().hasPrefix("pt") == true ? pt : en
}
