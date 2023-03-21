//
//  HighlightEditor.swift
//  Syntax Highlighter
//
//  Created by Haaris Iqubal on 5/23/21.
//

import SwiftUI

struct HighlightEditor:UIViewRepresentable{
    @Binding var text:String
    let textStorage = NSTextStorage()
    
    func makeUIView(context: Context) -> UITextView {
        let layoutManager = NSLayoutManager()
        let containers = NSTextContainer(size: CGSize())
        containers.widthTracksTextView = true
        layoutManager.addTextContainer(containers)
        textStorage.addLayoutManager(layoutManager)
        let view = UITextView(frame: CGRect(),textContainer: containers)
        let font = UIFont.systemFont(ofSize: 50)
        
        let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:UIColor.white]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        textStorage.append(attributedString)
        view.isScrollEnabled = true
        view.autocapitalizationType = .sentences
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        view.backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.00)
        
        return view
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        var replacements: [String:[NSAttributedString.Key:Any]] = [:]
        let tags = [NSAttributedString.Key.foregroundColor : UIColor.systemPink]
        replacements = ["(<([^>]+)>)":tags]
        for (pattern, attributes) in replacements{
            do{
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(text.startIndex...,in:text)
                regex.enumerateMatches(in: text, range: range){
                    match, flags, stop in
                    if let matchRange = match?.range(at: 0){
                        textStorage.addAttributes(attributes, range: matchRange)
                    }
                }
            }
            catch{
                print(error.localizedDescription)
            }
        }
    }
    
    typealias UIViewType = UITextView
    
}

struct PreviewHighlightEditor: PreviewProvider{
    static var previews: some View{
        ContentView()
    }
}
