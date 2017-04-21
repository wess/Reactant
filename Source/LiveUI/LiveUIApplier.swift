import UIKit
import SnapKit
import Reactant
import KZFileWatchers
import SWXMLHash

extension Array where Element == (String, UIView) {
    func named(_ name: String) -> UIView? {
        return first(where: { $0.0 == name })?.1
    }
}

public class ReactantLiveUIApplier {
    let root: Element.Root
    let instance: UIView
    let commonStyles: [Style]

    private var tempCounter: Int = 1

    public init(root: Element.Root, commonStyles: [Style], instance: UIView) {
        self.root = root
        self.commonStyles = commonStyles
        self.instance = instance
    }

    public func apply() throws {
        instance.subviews.forEach { $0.removeFromSuperview() }
        let views = try root.children.flatMap { try apply(element: $0, superview: instance) }
        tempCounter = 1
        try root.children.forEach { try applyConstraints(views: views, element: $0, superview: instance) }
    }

    private func apply(element: UIElement, superview: UIView) throws -> [(String, UIView)] {
        let name: String
        let view: UIView
        if let field = element.field {
            name = "\(field)"
            if instance.responds(to: Selector("\(field)")) {
                view = instance.value(forKey: field) as! UIView
            } else if let mirrorView = Mirror(reflecting: instance).children.first(where: { $0.label == name })?.value as? UIView {
                view = mirrorView
            } else {
                throw LiveUIError(message: "Undefined field \(field)")
            }
        } else if let layoutId = element.layout.id {
            name = "named_\(layoutId)"
            view = element.initialize()
        } else {
            name = "temp_\(type(of: element))_\(tempCounter)"
            tempCounter += 1
            view = element.initialize()
        }



        for property in try (commonStyles + root.styles).resolveStyle(for: element) {
            property.apply(property, view)
        }

        // FIXME This is a workaround, should not be doing it here (could move to the UIContainer)
        if let stackView = superview as? UIStackView {
            stackView.addArrangedSubview(view)
        } else {
            superview.addSubview(view)
        }

        if let container = element as? UIContainer {
            let children = try container.children.flatMap { try apply(element: $0, superview: view) }

            return [(name, view)] + children
        } else {
            return [(name, view)]
        }
    }

    private func applyConstraints(views: [(String, UIView)], element: UIElement, superview: UIView) throws {
        let name: String
        if let field = element.field {
            name = "\(field)"
        } else if let layoutId = element.layout.id {
            name = "named_\(layoutId)"
        } else {
            name = "temp_\(type(of: element))_\(tempCounter)"
            tempCounter += 1
        }

        guard let view = views.named(name) else {
            throw LiveUIError(message: "Couldn't find view with name \(name) in view hierarchy")
        }

        var error: LiveUIError?

        view.snp.remakeConstraints { make in
            for constraint in element.layout.constraints {
                let maker: ConstraintMakerExtendable
                switch constraint.anchor {
                case .top:
                    maker = make.top
                case .bottom:
                    maker = make.bottom
                case .leading:
                    maker = make.leading
                case .trailing:
                    maker = make.trailing
                case .left:
                    maker = make.left
                case .right:
                    maker = make.right
                case .width:
                    maker = make.width
                case .height:
                    maker = make.height
                case .centerX:
                    maker = make.centerX
                case .centerY:
                    maker = make.centerY
                case .firstBaseline:
                    maker = make.firstBaseline
                case .lastBaseline:
                    maker = make.lastBaseline
                case .size:
                    maker = make.size
                }

                let target: ConstraintRelatableTarget

                if let targetConstant = Float(constraint.target), constraint.anchor == .width || constraint.anchor == .height || constraint.anchor == .size {
                    target = targetConstant
                } else {
                    let targetName: String
                    if let colonIndex = constraint.target.characters.index(of: ":"), constraint.target.substring(to: colonIndex) == "id" {
                        targetName = "named_\(constraint.target.substring(from: constraint.target.characters.index(after: colonIndex)))"
                    } else {
                        targetName = constraint.target
                    }
                    guard let targetView = targetName != "super" ? views.named(targetName) : superview else {
                        error = LiveUIError(message: "Couldn't find view with name \(targetName) in view hierarchy")
                        return
                    }
                    if constraint.targetAnchor != constraint.anchor {
                        switch constraint.targetAnchor {
                        case .top:
                            target = targetView.snp.top
                        case .bottom:
                            target = targetView.snp.bottom
                        case .leading:
                            target = targetView.snp.leading
                        case .trailing:
                            target = targetView.snp.trailing
                        case .left:
                            target = targetView.snp.left
                        case .right:
                            target = targetView.snp.right
                        case .width:
                            target = targetView.snp.width
                        case .height:
                            target = targetView.snp.height
                        case .centerX:
                            target = targetView.snp.centerX
                        case .centerY:
                            target = targetView.snp.centerY
                        case .firstBaseline:
                            target = targetView.snp.firstBaseline
                        case .lastBaseline:
                            target = targetView.snp.lastBaseline
                        case .size:
                            target = targetView.snp.size
                        }
                    } else {
                        target = targetView
                    }
                }

                var editable: ConstraintMakerEditable
                switch constraint.relation {
                case .equal:
                    editable = maker.equalTo(target)
                case .greaterThanOrEqual:
                    editable = maker.greaterThanOrEqualTo(target)
                case .lessThanOrEqual:
                    editable = maker.lessThanOrEqualTo(target)
                }

                if constraint.constant != 0 {
                    editable = editable.offset(constraint.constant)
                }
                if constraint.multiplier != 1 {
                    editable = editable.multipliedBy(constraint.multiplier)
                }
                if constraint.priority.numeric != 1000 {
                    editable.priority(constraint.priority.numeric)
                }
            }
        }

        if let error = error {
            throw error
        }

        if let container = element as? UIContainer {
            try container.children.forEach { try applyConstraints(views: views, element: $0, superview: view) }
        }
    }
}