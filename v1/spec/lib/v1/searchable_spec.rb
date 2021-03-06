require 'v1/searchable'

#module Rails; end

# create fake 'searchable' resource
module SearchableItem
  extend V1::Searchable
end

module V1

  module Searchable 

    describe Searchable do

      before(:each) do
        stub_const("V1::Config::SEARCH_INDEX", "some_index")
        #Rails.stub_chain(:logger, :debug) { stub }
        subject.stub(:verbose_debug)
      end

      context "Module constants" do
        describe "DEFAULT_PAGE_SIZE" do
          it "has the correct value" do
            expect(DEFAULT_PAGE_SIZE).to eq 10
          end
        end
        
        describe "DEFAULT_MAX_PAGE_SIZE" do
          it "has the correct value" do
            expect(DEFAULT_MAX_PAGE_SIZE).to eq 100
          end
        end

        describe DEFAULT_SORT_ORDER do
          it "has the correct value" do
            expect(DEFAULT_SORT_ORDER).to eq "asc"
          end
        end

        describe "MAXIMUM_FACETS_COUNT" do
          it "has the correct value" do
            expect(MAXIMUM_FACETS_COUNT).to eq 'not implemented'
          end
        end

        describe "BASE_QUERY_PARAMS" do
          it "has the correct value" do
            expect(BASE_QUERY_PARAMS).to match_array %w( 
              q controller action sort_by sort_order page page_size facets fields callback
            )
          end
        end
      end
    end
  end

  describe SearchableItem do

    describe "#validate_params" do
      before(:each) do
        stub_const("V1::Searchable::BASE_QUERY_PARAMS", %w( q controller action ) )
      end
      it "compares against both BASE_QUERY_PARAMS and queryable_fields" do
        Schema.stub(:queryable_fields) { %w( title description ) }

        expect {
          SearchableItem.validate_params({'q' => 'banana'})
          SearchableItem.validate_params({'title' => 'curious george'})
        }.not_to raise_error BadRequestSearchError

        expect {
          SearchableItem.validate_params({'invalid_field' => 'banana'})
        }.to raise_error BadRequestSearchError, /invalid field/i
      end
    end

    describe "#fetch" do
      let(:result1) {
        {
          "count" => 1,
          "docs" => [{"_id" => "1"}]
        }
      }
      let(:result2) {
        {
          "count" => 1,
          "docs" => [{"_id" => "2"}]
        }
      }
      let(:error_stub){
        {
          "id" => "ccc",
          "error" => "404"
        }
      }
 
      it "delegates transformed ids to V1::Repository.fetch" do
        subject.should_receive(:search).with({"id" => "aaa" }) { result1 }
        V1::Repository.should_receive(:fetch).with(["1"]) # { repo_item_stub }
        subject.fetch(["aaa"])
      end

      it "accepts more than one item" do
        subject.stub(:search).twice.and_return(result1, result2)
        V1::Repository.should_receive(:fetch).with(["1", "2"])
        subject.fetch(["aaa", "bbb"])
      end

      it "can handle an item that does not exist" do
        repo_item_stub_1 = stub
        subject.stub(:search).twice.and_return(result1, {'count' => 0})
        V1::Repository.should_receive(:fetch).with(["1"]) { {'docs' => [repo_item_stub_1]} }
        expect(subject.fetch(["aaa", "ccc"])['docs']).to match_array( [repo_item_stub_1, error_stub] )
      end

      it "raises error when single item not found" do
        subject.stub(:search) { {'count' => 0} }
        expect { subject.fetch(["non-existent-ID"]) }.to raise_error(NotFoundSearchError)
      end

    end


    describe "build_sort_attributes" do
      it "returns nil when sort params are not present" do
        params = {'q' => 'banana'}
        expect(subject.build_sort_attributes(params)).to eq nil
      end

      it "returns a valid sort order if an invalid sort order param present" do
        params = {'q' => 'banana', 'sort_by' => 'title', 'sort_order' => 'apple'}
        expect(
          subject.build_sort_attributes(params)
        ).to eq ['title', Searchable::DEFAULT_SORT_ORDER]
      end

      it "returns the valid sort order if a valid sort order is param present" do
        params = {'q' => 'banana', 'sort_by' => 'title', 'sort_order' => 'desc'}
        expect(
          subject.build_sort_attributes(params)
        ).to eq ['title', 'desc']
      end

      it "returns a valid sort order param if no sort order param present" do
        params = {'q' => 'banana', 'sort_by' => 'title'}
        expect(
          subject.build_sort_attributes(params)
        ).to eq ['title', Searchable::DEFAULT_SORT_ORDER]
      end
    end

    describe "#parse_field_params" do
      it "raises SearchError if invalid field was sent" do
        params = {'q' => 'banana', 'fields' => 'invalid'}
        expect  { 
          subject.parse_field_params(params) 
        }.to raise_error BadRequestSearchError
      end
      it "returns an array from CSV params" do
        params = {'q' => 'banana', 'fields' => 'title,description'}
        expect(
          subject.parse_field_params(params)
        ).to eq ['title', 'description']
      end
      
      it "returns nil when no fields param present" do
        params = {'q' => 'banana'}
        expect(subject.parse_field_params(params)).to eq nil
      end
    end
   
    describe "#get_search_starting_point" do
      it "returns starting point based on 'page size' and the start page" do
        params = { "page" => "2", 'page_size' => "5" }
        expect(subject.get_search_starting_point(params)).to eq (5)
      end

      it "returns the starting point of 0 when called with non-integer param" do
        params = { "page" => "a" }
        expect(subject.get_search_starting_point(params)).to eq (0)
      end

      it "returns the starting point of zero when called with no  page param" do 
        params = {}
        expect(subject.get_search_starting_point(params)).to eq (0)
      end
    end

    describe "#get_search_size" do
      it "returns the default page size when a non-integer param is passed" do
        params = { "page_size" => "a" }
        expect(subject.get_search_size(params)).to eq(Searchable::DEFAULT_PAGE_SIZE)
      end

      it "returns the desired page size when a valid integer param is passed" do
        params = { "page_size" => "20" }
        expect(subject.get_search_size(params)).to eq (20)
      end

      it "returns the default page size when no search size param is passed" do
        params = {}
        expect(subject.get_search_size(params)).to eq (Searchable::DEFAULT_PAGE_SIZE)
      end

      it "returns the default max page size when the search size is greater than the max" do
        huge_size = Searchable::DEFAULT_MAX_PAGE_SIZE + 1
        params = { "page_size" => huge_size }
        expect(subject.get_search_size(params)).to eq (Searchable::DEFAULT_MAX_PAGE_SIZE)
      end
    end

    describe "#wrap_results" do
      let(:results)  { stub("results", :total => 10, :facets => nil) }
      let(:search) { stub("search", :results => results, :options => {:from => 0, :size => 10}) }
      let(:formatted_results) { stub }
      
      before(:each) do
        subject.stub(:reformat_results) { formatted_results }
      end
      
      it "wraps results set correctly without facets" do
        expect(
               subject.wrap_results(search)
               ).to eq({
                         'count' => 10,
                         'limit' => 10,
                         'start' => 0,
                         'docs' => formatted_results
                       })
      end
      it "wraps results set correctly with facets" do
        facets = stub
        results.stub(:facets) { facets }
        expect(
               subject.wrap_results(search)
               ).to eq({
                         'count' => 10,
                         'limit' => 10,
                         'start' => 0,
                         'docs' => formatted_results,
                         'facets' => facets
                       })
      end
    end

    describe "#reformat_results" do
      it "remaps elasticsearch item wrapper to collapse items to first level with score" do
        docs = [{
          "_score" => 1, 
          "_source" => {
            "_id" => "1",
            "_type" => "1",
            "title" => "banana",
            "description" => "desc"
          }
        }]
        expect(subject.reformat_results(docs)).to eq(
          [{
             "_id" => "1",
             "title" => "banana",
             "description" => "desc",
             "score" => 1
           }]
        )
      end

      it "remaps on fields key when no _source key present" do
        docs = [{
          "_index" => "dpla",
          "_type" => "item",
          "_id" => "1",
          "_score" => 1.0,
          "fields" => {"title" => "banana"}
        }]
        expect(subject.reformat_results(docs)).to match_array(
          [{"title" => "banana"}]
        )
      end
    end

    describe "#search" do
      let(:mock_search) { mock('mock_search').as_null_object }

      before(:each) do
        Tire.stub(:search).and_yield(mock_search)
        subject.stub(:wrap_results)
      end

      it "calls validates_params" do
        params = {}
        subject.should_receive(:validate_params).with(params)
        subject.search(params)
      end

      it "uses V1::Config::SEARCH_INDEX for its search index" do
        params = {'q' => 'banana'}
        Tire.should_receive(:search).with(V1::Config::SEARCH_INDEX) #.and_yield(mock_search)
        subject.search(params)
      end

      it "calls query, filter and facet build_all methods with correct params" do
        params = {'q' => 'banana'}
        V1::Searchable::Query.should_receive(:build_all).with(mock_search, params) { true }
        V1::Searchable::Filter.should_receive(:build_all).with(mock_search, params) { false }
        V1::Searchable::Facet.should_receive(:build_all).with(mock_search, params, !true)
        subject.search(params)
      end

      it "returns search.results() with dictionary wrapper" do
        params = {'q' => 'banana'}
        results = stub("results")
        dictionary_results = stub("dictionary_wrapped")
        mock_search.stub(:results) { results }
        subject.stub(:wrap_results).with(mock_search) { dictionary_results }
        expect(subject.search(params)).to eq dictionary_results
      end

      context "fields" do
        it "limits result fields returned" do
          params = {'q' => 'banana',  'fields' => 'title, description' }
          subject.stub(:parse_field_params) { ["title", "description"] }
          mock_search.should_receive(:fields)
          subject.search(params)
        end
        
        it "does not set field restrictions if not present" do
          params = {'q' => 'banana' }
          subject.stub(:parse_field_params) { nil }
          mock_search.should_not_receive(:fields)
          subject.search(params) 
        end
      end
      
      context "sorting" do
        it "sorts by field name if present" do
          params = {'q' => 'banana',  'sort_by' => 'title' }
          mock_search.should_receive(:sort)
          subject.should_receive(:wrap_results)
          subject.search(params)
        end

        it "does not implement custom sorting when no sort params present" do
          params = {'q' => 'banana'}
          mock_search.should_not_receive(:sort)
          subject.should_receive(:wrap_results)
          subject.search(params)
        end
      end

    end

  end

end
