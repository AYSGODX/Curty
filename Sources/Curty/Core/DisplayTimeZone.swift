import Foundation

/// Часовой пояс машины — единственное, что система знает о том, где человек
/// находится, и он не всегда правдив: можно жить во Вьетнаме с рабочим маком
/// на московском времени. Определять местоположение по-настоящему пришлось бы
/// геолокацией или запросом наружу — новое разрешение и новый адрес в сети
/// ради формата времени. Поэтому пояс задаётся руками, а по умолчанию его нет.
enum DisplayTimeZonePolicy {
    /// Пустая строка — «как в системе». Это же и умолчание, поэтому у всех,
    /// кто настройку не трогал, поведение остаётся ровно прежним. Незнакомый
    /// идентификатор тоже откатывается к системному: настройка не должна
    /// ломать показ времени, что бы в неё ни попало.
    static func resolve(identifier: String) -> TimeZone {
        guard !identifier.isEmpty, let zone = TimeZone(identifier: identifier) else {
            return .current
        }
        return zone
    }

    /// Отличается ли выбранный пояс от системного. По нему календарь решает,
    /// говорить ли, в каком времени показаны встречи: 19:00 в Curty против
    /// 15:00 в «Календаре» без объяснения читается как ошибка.
    static func isOverridden(identifier: String) -> Bool {
        resolve(identifier: identifier).secondsFromGMT() != TimeZone.current.secondsFromGMT()
    }

    /// Календарь с подставленным поясом: «сегодня» во Вьетнаме и «сегодня» в
    /// Москве — разные дни на четыре часа в сутки.
    static func calendar(for zone: TimeZone) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = zone
        return calendar
    }

    /// Список для выбора, сгруппированный по частям света: плоские шестьсот
    /// строк в меню шторки не помещаются никак.
    static var groupedIdentifiers: [(region: String, identifiers: [String])] {
        let grouped = Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers) { identifier in
            identifier.split(separator: "/").first.map(String.init) ?? "Прочие"
        }
        return grouped
            .map { (region: $0.key, identifiers: $0.value.sorted()) }
            .sorted { $0.region < $1.region }
    }

    /// «Asia/Ho_Chi_Minh» → «Ho Chi Minh»: в меню, разбитом по регионам,
    /// повторять регион в каждой строке незачем.
    static func cityName(_ identifier: String) -> String {
        let tail = identifier.split(separator: "/").dropFirst().joined(separator: " / ")
        let name = tail.isEmpty ? identifier : tail
        return name.replacingOccurrences(of: "_", with: " ")
    }
}
