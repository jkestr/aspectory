require 'spec/spec_helper'

describe Aspectory::Callbacker do
  attr_reader :klass, :subklass, :callbacker, :object
  
  before(:each) do
    @klass = Class.new do
      attr_reader :results
      
      def initialize
        @results = []
      end
      
      def no
        false
      end
      
      def foo(arg=:foo, &block)
        @results << (block_given? ? block.call : arg)
        arg
      end

      def bar(arg=:bar, &block)
        return arg unless arg
        @results << (block_given? ? block.call : arg)
      end
      
      def bar!(arg)
        @results << arg
      end
      
      def bar=(arg)
        @results << arg
      end
      
      def bar?(arg)
        @results << (arg == :bar)
      end
      
      def wrapify
        @results << :before
        yield
        @results << :after
      end
      
      def pitch
        throw :foo, :result
      end
    end
    
    @callbacker = Aspectory::Callbacker.new(klass)
    @object = klass.new
  end
  
  describe "klass#__PRISTINE__" do
    it "allows original method calling" do
      callbacker.before(:foo) { @results << :before }
      
      object.__PRISTINE__(:foo)
      object.results.should == [:foo]
    end
    
    it "allows arguments" do
      callbacker.before(:foo) { @results << :before }
      
      object.__PRISTINE__(:foo, :bar)
      object.results.should == [:bar]
    end
    
    it "allows a block" do
      callbacker.before(:foo) { @results << :before }
      
      object.__PRISTINE__(:foo) { :bar }
      object.results.should == [:bar]
    end
    
    it "raises when method doesn't exist" do
      proc {
        callbacker.__PRISTINE__(:whiz)
      }.should raise_error(NoMethodError)
    end
    
    describe "*_without_callbacks methods" do
      it "are generated for methods with callbacks" do
        callbacker.before(:foo) { @results << :before }

        object.foo_without_callbacks
        object.results.should == [:foo]
      end
      
      it "are generated for bang methods" do
        callbacker.before(:bar!) { @results << :before }
        
        object.bar_without_callbacks! :bar
        object.results.should == [:bar]
      end
      
      it "are generated for predicate methods" do
        callbacker.before(:bar?) { @results << :before }
        
        object.bar_without_callbacks? :bar
        object.results.should == [true]
      end
      
      it "are generated for assignment methods" do
        callbacker.before(:bar=) { @results << :before }
        
        object.bar_without_callbacks = :bar
        object.results.should == [:bar]
      end
    end
  end
  
  describe "#before" do
    context "with a block" do
      it "defines before behavior" do
        callbacker.before(:foo) { @results << :before }

        object.foo
        object.results.should == [:before, :foo]
      end
      
      describe "special method name endings" do
        it "works with bang methods" do
          callbacker.before(:bar=) { @results << :banged }
          object.bar = :bar
          object.results.should == [:banged, :bar]
        end
        
        it "works with predicate methods" do
          callbacker.before(:bar?) { @results << :banged }
          object.bar?(:bar)
          object.results.should == [:banged, true]
        end
      end
      
      describe "subclass behavior" do
        before(:each) do
          callbacker.before(:foo) { @results << :before }
          @subklass = Class.new(klass)
          @object = @subklass.new
        end
        
        it "runs superclass' callbacks" do
          object.foo
          object.results.should == [:before, :foo]
        end
        
        it "works with subclasses of subclasses" do
          subsubklass = Class.new(subklass)
          subobject = subsubklass.new
          subobject.foo
          subobject.results.should == [:before, :foo]
        end
        
        it "has subclass specific callbacks" do
          callbacker.before(:bar) { @results << :subbed }
          object.bar
          object.results.should == [:before, :subbed, :bar]
        end
      end
      
      describe "redefining methods" do
        it "allows arguments" do
          callbacker.before(:foo) { @results << :before }

          object.foo(:arg)
          object.results.should == [:before, :arg]
        end

        it "allows a block" do
          callbacker.before(:foo) { @results << :before }

          object.foo { :block }
          object.results.should == [:before, :block]
        end

        it "only happens once" do
          mock(callbacker).redefine_method(anything).once
          callbacker.before(:foo) { true }
          callbacker.before(:foo) { false }
        end
      end

      describe "callback blocks" do
        it "enables halting of method call" do
          callbacker.before(:foo) { false }

          object.foo
          object.results.should be_empty
        end

        it "can be more than one per method" do
          callbacker.before(:foo) { ping! }
          callbacker.before(:foo) { pong! }

          mock(object) do |expect|
            expect.ping!
            expect.pong!
          end

          object.foo
        end

        describe "throwing alternative result" do
          before(:each) do
            callbacker.before(:foo) { throw :foo, :result }
          end
          
          it "returns alternative" do
            object.foo.should == :result
          end
          
          it "doesn't run original method" do
            object.results.should be_empty
          end
        end
      end
    end
    
    context "with a symbol" do
      it "defines before behavior" do
        callbacker.before(:foo, :bar)

        object.foo
        object.results.should == [:bar, :foo]
      end

      describe "redefining methods" do
        it "allows arguments" do
          callbacker.before(:foo, :bar)

          object.foo(:arg)
          object.results.should == [:bar, :arg]
        end

        it "allows a block" do
          callbacker.before(:foo, :bar)

          object.foo { :block }
          object.results.should == [:bar, :block]
        end
      end

      describe "callback blocks" do
        it "enables halting of method call" do
          callbacker.before(:foo, :no)

          object.foo
          object.results.should be_empty
        end

        it "can be more than one per method" do
          callbacker.before(:foo, :ping!)
          callbacker.before(:foo, :pong!)

          mock(object) do |expect|
            expect.ping!
            expect.pong!
          end

          object.foo
        end
        
        it "doesn't run same callback twice for same method" do
          callbacker.before(:foo, :ping!)
          callbacker.before(:foo, :ping!)
          
          mock(object).ping!.once
          
          object.foo
        end
      end
    end
  end
  
  describe "#after" do
    context "with a block" do
      it "defines after behavior" do
        callbacker.after(:foo) { @results << :after }

        object.foo
        object.results.should == [:foo, :after]
      end
      
      describe "redefining methods" do
        it "allows arguments" do
          callbacker.after(:foo) { @results << :after }

          object.foo(:arg)
          object.results.should == [:arg, :after]
        end

        it "allows a block" do
          callbacker.after(:foo) { @results << :after }

          object.foo { :block }
          object.results.should == [:block, :after]
        end

        it "only happens once" do
          mock(callbacker).redefine_method(anything).once

          callbacker.after(:bar) { true }
          callbacker.after(:bar) { false }
        end
      end
      
      describe "special method name endings" do
        it "works with bang methods" do
          callbacker.after(:bar=) { @results << :banged }
          object.bar = :bar
          object.results.should == [:bar, :banged]
        end
        
        it "works with predicate methods" do
          callbacker.after(:bar?) { @results << :banged }
          object.bar?(:bar)
          object.results.should == [true, :banged]
        end
      end
      
      describe "subclass behavior" do
        before(:each) do
          callbacker.after(:foo) { @results << :after }
          @subklass = Class.new(klass)
          @object = @subklass.new
        end
        
        it "runs superclass' callbacks" do
          object.foo
          object.results.should == [:foo, :after]
        end
        
        it "works with subclasses of subclasses" do
          subsubklass = Class.new(subklass)
          subobject = subsubklass.new
          subobject.foo
          subobject.results.should == [:foo, :after]
        end
        
        it "has subclass specific callbacks" do
          callbacker.after(:bar) { @results << :subbed }
          object.bar
          object.results.should == [:bar, :after, :subbed]
        end
      end

      describe "callback blocks" do
        it "cannot enable halting of method call" do
          callbacker.after(:foo) { false }

          object.foo
          object.results.should == [:foo]
        end
        
        it "still gets called when method returns false" do
          callbacker.after(:bar?) { @results << :called }
          object.bar?(:foo)
          object.results.should == [false, :called]
        end

        it "can be more than one per method" do
          callbacker.after(:foo) { ping! }
          callbacker.after(:foo) { pong! }

          mock(object).ping!
          mock(object).pong!

          object.foo
        end

        it "gets access to result of method call" do
          callbacker.after(:foo) { |result| @results << result }

          object.foo
          object.results.should == [:foo, :foo]
        end

        it "can throw alternative result" do
          callbacker.after(:foo) { throw :foo, :result }

          object.foo.should == :result
        end
      end
    end
    
    context "with a symbol" do
      it "defines after behavior" do
        callbacker.after(:foo, :bar?)

        object.foo
        object.results.should == [:foo, false]
      end
      
      it "doesn't run same callback twice for same method" do
        callbacker.after(:foo, :ping!)
        callbacker.after(:foo, :ping!)
        
        mock(object).ping!(anything).once
        
        object.foo
      end

      describe "redefining methods" do
        it "allows arguments" do
          callbacker.after(:foo, :bar?)

          object.foo(:bar)
          object.results.should == [:bar, true]
        end

        it "allows a block" do
          callbacker.after(:foo, :bar)

          object.foo { :block }
          object.results.should == [:block, :foo]
        end
      end

      describe "callback blocks" do
        it "cannot enable halting of method call" do
          callbacker.after(:foo, :no)

          object.foo
          object.results.should == [:foo]
        end
        
        it "gets access to result of method call" do
          callbacker.after(:foo, :bar)

          object.foo(:arg)
          object.results.should == [:arg, :arg]
        end
        
        it "can be more than one per method" do
          callbacker.after(:foo, :ping!)
          callbacker.after(:foo, :pong!)

          mock(object).ping!.with(:foo)
          mock(object).pong!.with(:foo)

          object.foo
        end

        it "can throw alternative result" do
          callbacker.after(:foo, :pitch)

          object.foo.should == :result
        end
      end
    end
  end
  
  describe "#around" do
    context "with a block" do
      it "returns proper result" do
        callbacker.around(:foo) do |fn|
          @results << :before
          fn.call
          @results << :after
        end
        
        object.foo.should == :foo
      end
      
      it "defines after behavior" do
        callbacker.around(:foo) do |fn|
          @results << :before
          fn.call
          @results << :after
        end

        object.foo
        object.results.should == [:before, :foo, :after]
      end
      
      describe "redefining methods" do
        it "allows arguments" do
          callbacker.around(:foo) do |fn|
            @results << :before
            fn.call
            @results << :after
          end
    
          object.foo(:arg)
          object.results.should == [:before, :arg, :after]
        end
    
        it "allows a block" do
          callbacker.around(:foo) do |fn|
            @results << :before
            fn.call
            @results << :after
          end
            
          object.foo { :block }
          object.results.should == [:before, :block, :after]
        end
   
        it "only happens once" do
          mock(callbacker).redefine_method(anything).once
            
          callbacker.around(:bar) { true }
          callbacker.around(:bar) { false }
        end
      end
      
      describe "special method name endings" do
        it "works with bang methods" do
          callbacker.around(:bar!) do |fn|
            @results << :before
            fn.call
            @results << :after
          end
          object.bar! :bar
          object.results.should == [:before, :bar, :after]
        end
        
        it "works with predicate methods" do
          callbacker.around(:bar?) do |fn|
            @results << :before
            fn.call
            @results << :after
          end
          object.bar?(:bar)
          object.results.should == [:before, true, :after]
        end
        
        it "works with assignment methods" do
          callbacker.around(:bar=) do |fn|
            @results << :before
            fn.call
            @results << :after
          end
          object.bar = :bar
          object.results.should == [:before, :bar, :after]
        end
      end
      
      describe "subclass behavior" do
        before(:each) do
          callbacker.around(:foo) do |fn|
            @results << :before
            fn.call
            @results << :after
          end
          @subklass = Class.new(klass)
          @object = @subklass.new
        end
        
        it "runs superclass' callbacks" do
          object.foo
          object.results.should == [:before, :foo, :after]
        end
        
        it "works with subclasses of subclasses" do
          subsubklass = Class.new(subklass)
          subobject = subsubklass.new
          subobject.foo
          subobject.results.should == [:before, :foo, :after]
        end
        
        it "has subclass specific callbacks" do
          callbacker.after(:bar) { @results << :subbed }
          object.bar
          object.results.should == [:before, :bar, :after, :subbed]
        end
      end
    
      describe "callback blocks" do
        it "can enable halting of method call" do
          callbacker.around(:foo) { false }
    
          object.foo
          object.results.should be_empty
        end
    
        it "can be more than one per method" do
          callbacker.around(:foo) { ping! }
          callbacker.around(:foo) { pong! }
            
          mock(object).ping!
          mock(object).pong!
            
          object.foo
        end
            
        it "can throw alternative result" do
          callbacker.around(:foo) { |fn| fn.call and throw :foo, :result }
            
          object.foo.should == :result
        end
      end
    end
    
    context "with a symbol" do
      it "returns proper result" do
        callbacker.around(:foo, :wrapify)
        
        object.foo.should == :foo
      end
      
      it "defines after behavior" do
        callbacker.around(:foo, :wrapify)
    
        object.foo
        object.results.should == [:before, :foo, :after]
      end
      
      it "doesn't run same callback twice for same method" do
        callbacker.around(:foo, :ping!)
        callbacker.around(:foo, :ping!)
        
        mock(object).ping!.once
        
        object.foo
      end
    
      describe "redefining methods" do
        it "allows arguments" do
          callbacker.around(:foo, :wrapify)
    
          object.foo(:bar)
          object.results.should == [:before, :bar, :after]
        end
    
        it "allows a block" do
          callbacker.around(:foo, :wrapify)
    
          object.foo { :block }
          object.results.should == [:before, :block, :after]
        end
      end
    
      describe "callback blocks" do
        it "can be more than one per method" do
          callbacker.around(:foo, :ping!)
          callbacker.around(:foo, :pong!)
    
          mock(object).ping!
          mock(object).pong!
    
          object.foo
        end
    
        it "can throw alternative result" do
          callbacker.around(:foo, :pitch)
    
          object.foo.should == :result
        end
      end
    end
  end
end