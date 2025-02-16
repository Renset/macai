///
/// @file       SwipeModifier
///
/// @brief      SwipeModifier is designed to <#Description#>
///
/// @discussion <#Discussion#>
///
/// Written by Lloyd Sargent
///
/// Created May 11, 2024
///
/// Copyright © 2024 Canna Software LLC. All rights reserved.
///
/// Licensed under MIT license.
///

import SwiftUI

extension View {
    ///
    ///    View modifier to handle mouse swipes.
    ///
    ///    This view modifier is designed to handle mouse swipes for macOS.
    ///    Assume that `yourView` is the view you want to detect swipes on.
    ///
    ///        yourView
    ///            .onSwipe{ event in
    ///                    switch event.direction {
    ///                        case .south:
    ///                            print("### down")
    ///                        case .north:
    ///                            print("### up")
    ///                        case .west:
    ///                            print("### left")
    ///                        case .east:
    ///                            print("### right")
    ///                        default:
    ///                            print("### everythingelse")
    ///                    }
    ///            }
    ///
    ///    Note that modifiers are also passed into the event. This allows swipes using
    ///
    ///       ⌃ - control key
    ///
    ///       ⌥ - option key
    ///
    ///       ⌘ - command key
    ///
    ///
    ///    - Parameters:
    ///        - action: closure to call with the SwipeEvent as the parameter - @escaping(SwipeEvent) -> Void
    ///        - returns: ContentView - some View
    ///    #### ⚠︎ Warning
    ///    Has not been throughly tested with other modifiers..
    ///    ####  ⃠ Do Not Use
    ///    Will not work with iOS. This is a macOS solution. Use gestures with iOS.
    ///

    func onSwipe(perform action: @escaping (SwipeEvent) -> Void) -> some View {
        modifier(OnSwipe(action: action))
    }
}



///
///    Class containing information for when the user swipes on the magic mouse.
///
///    This contains more than enough variables to suit you.
///
///    >Note NSEvent is not used as it does not have enough information. Since it is more important to
///    know things like directionp.
///

public class SwipeEvent {
    enum SwipeDirection {
        case none, up, down, left, right
    }
    
    enum Modifier {
        case none, shift, control, option, command
    }
    
    enum Compass {
        case none, north, south, west, east, northWest, southWest, northEast, southEast
    }
    
    var nsevent: NSEvent! = nil
    
    var directionValue: CGFloat = .zero
    var phase: NSEvent.Phase = .mayBegin
    
    var deltaX: CGFloat = .zero
    var deltaY: CGFloat = .zero
    var location: CGPoint = .zero
    var timestamp: TimeInterval = .nan
    var mouseLocation: CGPoint = .zero
    var scrollingDeltaX: CGFloat = .zero
    var scrollingDeltaY: CGFloat = .zero
    var modifierFlags: NSEvent.ModifierFlags = .shift
    


    ///
    ///    Initialize the class.
    ///
    ///    Initializes the class with the NSEvent.
    ///
    ///    - Parameters:
    ///        - event: The event used by the modifier - NSEvent
    ///    #### ！Attention
    ///    Guards against the event window being nil. This is a bit of a hack as events can occur that
    ///    are not attached to a view. Since we ONLY want events that are attached to views, these
    ///    events are filtered out.
    ///

    init(event: NSEvent) {
        nsevent = event
        guard nsevent.window != nil else { return }

        //----- copy the nsevent data
        scrollingDeltaX = nsevent.scrollingDeltaX
        scrollingDeltaY = nsevent.scrollingDeltaY
        phase = nsevent.phase
        deltaX = nsevent.deltaX
        deltaY = nsevent.deltaY
        scrollingDeltaX = nsevent.scrollingDeltaX
        scrollingDeltaY = nsevent.scrollingDeltaY
        location = nsevent.locationInWindow
        mouseLocation = nsevent.locationInWindow
        location = nsevent.cgEvent!.location
        timestamp = nsevent.timestamp
    }



    ///
    ///    This is an oversimplified version of the scrollWheel.
    ///
    ///    Normally a simple version of the scrollWheel is not a problem. This will satisfy most use
    ///    cases.
    ///
    ///    - returns: Swipe direction - enum Compass
    ///    #### ⓘ Interest
    ///    Although it seems squished, the if statements have been reduced to a single line that makes
    ///    the code a little more readable.
    ///    #### ！Attention
    ///    If the wheel direction is at an angle, for example left and up, it will report `.left` and
    ///    the same with right and up, it will respond with `.right`. This really isn't normally a
    ///    problem unless you need more degrees of movement. In which case, you should go with the
    ///    `compass`.

    var direction: SwipeDirection {
        if nsevent.scrollingDeltaX > 0.0 { return .left  }
        if nsevent.scrollingDeltaX < 0.0 { return .right }
        if nsevent.scrollingDeltaY > 0.0 { return .up    }
        if nsevent.scrollingDeltaY < 0.0 { return .down  }
        
        return .none
    }



    ///
    ///    The scrollWheel as a compass
    ///
    ///    This has more granularity than a simple up/down/left/right with it broken down as
    ///    `north/south/east/west/northEast/northWest/southEast/southWest` allowing the user a greater
    ///    more flexibility.
    ///
    ///    - returns: swipe as a compass of directions - enum Compass
    ///    #### ⓘ Interest
    ///    By returning a compass, the user gets more flexibilty
    ///

    var compass: Compass {
        var directionEastWest: Compass = .none
        var directionNorthSouth: Compass = .none
        
        if nsevent.scrollingDeltaX > 0.0 { directionEastWest   = .east  }
        if nsevent.scrollingDeltaX < 0.0 { directionEastWest   = .west  }
        if nsevent.scrollingDeltaY > 0.0 { directionNorthSouth = .north }
        if nsevent.scrollingDeltaY < 0.0 { directionNorthSouth = .south }
        
        if nsevent.scrollingDeltaY == 0 { return directionEastWest   }
        if nsevent.scrollingDeltaX == 0 { return directionNorthSouth }
    
        if directionNorthSouth == .north && directionEastWest == .east { return .northEast }
        if directionNorthSouth == .south && directionEastWest == .east { return .southEast }
        if directionNorthSouth == .north && directionEastWest == .west { return .northWest }
        if directionNorthSouth == .south && directionEastWest == .west { return .southWest }
        
        return .none
    }

    
    
    ///
    ///    Simplifies the modifier.
    ///
    ///    Seldom do people use a combination of modifiers with the scrollWheel. This simplifies the
    ///    code.
    ///
    ///    - returns: the modifier key - Modifier
    ///    #### ⓘ Interest
    ///    While the contains is more flexibily, it makes the code look messy.
    ///

    var modifier: Modifier {
        if nsevent.modifierFlags.contains(.shift)   { return .shift   }
        if nsevent.modifierFlags.contains(.control) { return .control }
        if nsevent.modifierFlags.contains(.option ) { return .option  }
        if nsevent.modifierFlags.contains(.command) { return .command }
        
        return  .none
    }
}



///
///    A ViewModifier for detecting swipe events.
///
///    The view modifier creates uses hover to determine if the event occurs in the view.
///
///    - Parameters:
///        - : action contains the closure
///
///    - returns: The view (some View)
///    #### ！Attention
///    This uses the `.onContinousHover` modifier to determine if we are in the view.
///    #### ⚠︎ Warning
///    Do not remove the `.onDisappear` or you will leak memory.
///

private struct OnSwipe: ViewModifier {
    //----- our action closure
    var action: (SwipeEvent) -> Void
    
    //----- are we inside the view?
    @State private var insideViewWindow = false
    
    //----- swipe event
    @State private var swipeEvent = SwipeEvent(event: NSEvent())
    
    //----- secret sauce to prevent memory leaks DO NOT REMOVE
    @State private var monitor: Any? = nil
    
    func body(content: Content) -> some View {
        return content
            //----- see if we are in the view
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    insideViewWindow = true
                    
                case .ended:
                    insideViewWindow = false
                }
            }
        
            //----- view appear, add the monitor for scrollWheel events
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
                    
                    if insideViewWindow {
                        let scrollEvent = SwipeEvent(event: event)
                        action(scrollEvent)
                    }
                    
                    return event
                }
            }
        
            //----- onDisappear, remove the monitor to prevent memory leaks.
            .onDisappear {
                NSEvent.removeMonitor(monitor!)
            }
    }
}

