require "test_helper"

class CheckRespondsToTest < Minitest::Spec
  describe "#check_interfaces" do
    describe "unknown methods" do
      before do
        @code = <<~CODE
          module Sample
            class MyClass
              def initialize(user)
                @user = user
              end

              def name
                @user.name
              end
            end
          end
        CODE
      end

      it "yields an error when an unknown method is called" do
        config = CheckRespondsTo::Config.new({
          variable_to_class: {
            "user" => "User"
          },
          method_map: {
            "User" => {}
          }
        })
        checker = CheckRespondsTo::Checker.new(config)
        result = checker.check_interfaces(@code)

        assert result.errors.any?
      end

      it "yields no error when a known method is called" do
        config = CheckRespondsTo::Config.new({
          variable_to_class: {
            "user" => "User"
          },
          method_map: {
            "User" => {
              "name" => {
                arity: 0
              }
            }
          }
        })
        checker = CheckRespondsTo::Checker.new(config)
        result = checker.check_interfaces(@code)

        assert result.errors.none?
      end
    end

    describe "arity mismatch" do
      before do
        @code = <<~CODE
          module Sample
            class MyClass
              def initialize(user)
                @user = user
              end

              def name
                @user.name_of(:dog, :cat) { |hello| :world }
              end
            end
          end
        CODE
      end

      it "yields an error when the arity doesn't match (< actual)" do
        config = CheckRespondsTo::Config.new({
          variable_to_class: {
            "user" => "User"
          },
          method_map: {
            "User" => {
              "name_of" => {
                arity: 3
              }
            }
          }
        })
        checker = CheckRespondsTo::Checker.new(config)
        result = checker.check_interfaces(@code)

        assert result.errors.any?
      end

      it "yields an error when the arity doesn't match (< actual when actual is negative)" do
        config = CheckRespondsTo::Config.new({
          variable_to_class: {
            "user" => "User"
          },
          method_map: {
            "User" => {
              "name_of" => {
                arity: -4
              }
            }
          }
        })
        checker = CheckRespondsTo::Checker.new(config)
        result = checker.check_interfaces(@code)

        assert result.errors.any?
      end

      it "yields an error when the arity doesn't match (> actual)" do
        config = CheckRespondsTo::Config.new({
          variable_to_class: {
            "user" => "User"
          },
          method_map: {
            "User" => {
              "name_of" => {
                arity: 1
              }
            }
          }
        })
        checker = CheckRespondsTo::Checker.new(config)
        result = checker.check_interfaces(@code)

        assert result.errors.any?
      end

      it "yields no error when the arity matches (-1 arity)" do
        config = CheckRespondsTo::Config.new({
          variable_to_class: {
            "user" => "User"
          },
          method_map: {
            "User" => {
              "name_of" => {
                arity: -1
              }
            }
          }
        })
        checker = CheckRespondsTo::Checker.new(config)
        result = checker.check_interfaces(@code)

        assert result.errors.none?
      end

      it "yields no error when the arity matches (-2 arity)" do
        config = CheckRespondsTo::Config.new({
          variable_to_class: {
            "user" => "User"
          },
          method_map: {
            "User" => {
              "name_of" => {
                arity: -2
              }
            }
          }
        })
        checker = CheckRespondsTo::Checker.new(config)
        result = checker.check_interfaces(@code)

        assert result.errors.none?
      end

      it "yields no error when the arity matches (2 arity)" do
        config = CheckRespondsTo::Config.new({
          variable_to_class: {
            "user" => "User"
          },
          method_map: {
            "User" => {
              "name_of" => {
                arity: 2
              }
            }
          }
        })
        checker = CheckRespondsTo::Checker.new(config)
        result = checker.check_interfaces(@code)

        assert result.errors.none?
      end
    end
  end
end
