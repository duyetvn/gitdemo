class DocumentsController < ApplicationController
  before_action :set_document, only: [:show, :edit, :update, :destroy]

  def index
    @documents = Document.all
  end

  def show
  end

  def new
    @document = Document.new
  end

  def edit
    $document = Document.find_by(id: params[:id])
    @data = {document: @document}
  end

  def create
    @document = Document.new(document_params)

    respond_to do |format|
      if @document.save
        format.html { redirect_to @document, notice: 'Document was successfully created.' }
        format.json { render :show, status: :created, location: @document }
      else
        format.html { render :new }
        format.json { render json: @document.errors, status: :unprocessable_entity }
      end
    end
    create_revision(revision_params, 1, @document.id)
    @document.update_attributes(lastest_revision: @document.revisions.last.version_id)
  end

  def update
    unless params[:ver_restore].present?
      if (params[:document][:lastest_revision].to_i + 1) > @document.revisions.last.version_id
        respond_to do |format|
          if @document.update(document_params)
            format.html { redirect_to @document, notice: 'Document was successfully updated.' }
            format.json { render :show, status: :ok, location: @document }
          else
            format.html { render :edit }
            format.json { render json: @document.errors, status: :unprocessable_entity }
          end
        end
        version_id = @document.revisions.last.version_id
        new_version_id = version_id + 1
        create_revision(revision_params, new_version_id, params[:id])
        @document.update_attributes(lastest_revision: @document.revisions.last.version_id)
      else
        if @document.description.strip != params[:document][:description].strip
          @original = @document.description
          @current  = params[:document][:description]
          @diff = Differ.diff_by_line(@current, @original)
          @document.description = @diff
          @result = ""
          conflict = false
          @document.description.split("\n").each do |line|
            match_line = /(.*){(.*)}(.*)/.match(line)
            if match_line
              @result.concat(match_line[1]).concat("\n")
              line_change = /\"(.*)\" >> \"(.*)\"/.match(match_line[2])
              line_add = /[\+]\"(.*)\"/.match(match_line[2])
              line_remove = /[\-]\"(.*)\"/.match(match_line[2])
              if line_change
                binding.pry
                @result.concat("<<<<< HEAD \n").concat(line_change[1]).concat("\n =====\n").concat(line_change[2]).concat("\n >>>>> your change\n")
                conflict = true
              elsif line_add
                @result.concat(line_add[1])
              elsif line_remove
                @result.concat(line_remove[1])
              end
              # @result.concat(match_line[2]).concat("\n")
              @result.concat(match_line[3])
            else
              @result.concat(line)
            end
          end

          if conflict
            @document.description = @result
            @result.gsub!("\\n","\n").gsub!("\\r","\r")
            @document.update_attributes(lastest_revision: @document.revisions.last.version_id)
            flash[:warning] = "Conflicted"
            render :edit
          else
            @result.gsub!("\\n","\n").gsub!("\\r","\r")
            @document.update_attributes(description: @result)
            version_id = @document.revisions.last.version_id
            new_version_id = version_id + 1
            create_revision(revision_params, new_version_id, params[:id])
            @document.update_attributes(lastest_revision: Revision.last.version_id)
            redirect_to @document
            flash[:warning] = "Auto merged"
          end
        else
          flash[:warning] = "Auto merged"
          redirect_to @document
        end
      end
    else
      @restore_revision = Revision.find_by(id: params[:ver_restore])
      @document.update_attributes(title: @restore_revision.title,
        description: @restore_revision.description, lastest_revision: @document.lastest_revision + 1)
      Revision.create(title: @restore_revision.title, description: @restore_revision.description,
         document_id: params[:id], version_id: @document.revisions.last.version_id.to_i + 1)
      redirect_to @document
    end
  end

  def destroy
    @document.destroy
    respond_to do |format|
      format.html { redirect_to documents_url, notice: 'Document was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    def set_document
      @document = Document.find(params[:id])
    end

    def document_params
      params.require(:document).permit(:title, :description, :lastest_revision)
    end

    def revision_params
      params.require(:document).permit(:title, :description)
    end

    def create_revision params, version_id, document_id
      @revision = Revision.new(params)
      @revision.save
      @revision.update_attributes(document_id: document_id, version_id: version_id)
    end
end
