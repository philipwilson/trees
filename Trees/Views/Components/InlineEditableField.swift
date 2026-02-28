import SwiftUI

enum EditableField: Hashable {
    case species
    case variety
    case rootstock
}

struct InlineEditableField: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    var focusedField: FocusState<EditableField?>.Binding
    let field: EditableField
    let nextField: EditableField?

    var body: some View {
        TextField(label, text: $value, prompt: Text(placeholder))
            .focused(focusedField, equals: field)
            .onSubmit {
                focusedField.wrappedValue = nextField
            }
    }
}
